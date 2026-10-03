#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import Testing

@testable import DyldToolbox

@Suite("MachOImageScanner memory protection", .serialized)
struct MachOImageScannerMemoryTests {
    @Test("a read-only page can be written and its protection restored")
    func writesOwnedPageAndRestoresReadOnlyProtection() throws {
        let pageSize = Int(sysconf(_SC_PAGESIZE))
        try #require(pageSize > 0)
        let page = try #require(mmap(nil, pageSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))
        try #require(page != MAP_FAILED)
        defer { #expect(munmap(page, pageSize) == 0) }

        let slot = page.advanced(by: MemoryLayout<UInt>.size).assumingMemoryBound(to: UInt.self)
        slot.pointee = 123
        try #require(mprotect(page, pageSize, PROT_READ) == 0)

        let slotAddress = UInt(bitPattern: slot)
        let errorNumber = MachOImageScanner.withWritableMemory(
            startAddress: slotAddress,
            endAddress: slotAddress + UInt(MemoryLayout<UInt>.size),
            restoringProtection: PROT_READ
        ) {
            slot.pointee = 456
        }

        #expect(errorNumber == nil)
        #expect(slot.pointee == 456)
        let region = try leafVMRegion(containing: slotAddress)
        #expect(region.protection == VM_PROT_READ)
    }

    @Test("a page with read-only maximum protection cannot open for writing")
    func readOnlyMaximumProtectionDoesNotRunBody() throws {
        let pageSize = Int(sysconf(_SC_PAGESIZE))
        try #require(pageSize > 0)
        let page = try #require(mmap(nil, pageSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0))
        try #require(page != MAP_FAILED)
        defer { #expect(munmap(page, pageSize) == 0) }

        let startAddress = UInt(bitPattern: page)
        try #require(vm_protect(
            mach_task_self_,
            vm_address_t(startAddress),
            vm_size_t(pageSize),
            1,
            VM_PROT_READ
        ) == KERN_SUCCESS)

        var bodyRan = false
        let errorNumber = MachOImageScanner.withWritableMemory(
            startAddress: startAddress,
            endAddress: startAddress + UInt(MemoryLayout<UInt>.size),
            restoringProtection: PROT_READ
        ) {
            bodyRan = true
        }

        #expect(errorNumber == EACCES)
        #expect(!bodyRan)
    }
}

func leafVMRegion(containing address: UInt) throws -> vm_region_submap_short_info_data_64_t {
    var depth: natural_t = 0
    while true {
        var regionAddress = vm_address_t(address)
        var regionSize: vm_size_t = 0
        var info = vm_region_submap_short_info_data_64_t()
        let infoCapacity = mach_msg_type_number_t(
            MemoryLayout<vm_region_submap_short_info_data_64_t>.size / MemoryLayout<integer_t>.size
        )
        var infoCount = infoCapacity
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(infoCapacity)) { infoPointer in
                vm_region_recurse_64(
                    mach_task_self_,
                    &regionAddress,
                    &regionSize,
                    &depth,
                    infoPointer,
                    &infoCount
                )
            }
        }
        try #require(result == KERN_SUCCESS, "VM query failed for slot 0x\(String(address, radix: 16))")
        try #require(infoCount == infoCapacity)
        try #require(address >= UInt(regionAddress) && address - UInt(regionAddress) < UInt(regionSize))
        if info.is_submap == 0 { return info }
        depth += 1
    }
}

#endif
