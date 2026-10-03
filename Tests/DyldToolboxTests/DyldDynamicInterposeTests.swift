#if canImport(Darwin) && _pointerBitWidth(_64)

import Darwin
import Testing

@testable import DyldToolbox

/// `getppid` is the target on purpose: nothing else in this process calls it,
/// so redirecting it cannot disturb the test runner even while the interpose
/// is live.
private let interposedParentProcessIdentifier: pid_t = 424_242

@DyldDynamicInterpose(getppid)
func interposedGetParentProcessIdentifier() -> pid_t {
    interposedParentProcessIdentifier
}

@Suite("DyldDynamicInterpose", .serialized)
struct DyldDynamicInterposeTests {

    @Test("the macro plants a tuple pointing at the function being replaced")
    func registryContainsDeclaredTuple() {
        let tuples = DyldDynamicInterpose.registeredTuples()
        let expectedReplacee = unsafeBitCast(
            getppid as @convention(c) () -> pid_t,
            to: UnsafeRawPointer.self
        )
        let expectedReplacement = unsafeBitCast(
            interposedGetParentProcessIdentifier as @convention(c) () -> pid_t,
            to: UnsafeRawPointer.self
        )

        #expect(tuples.contains(
            DyldDynamicInterposeTuple(replacement: expectedReplacement, replacee: expectedReplacee)
        ))
    }

    /// The whole apply/observe/revert cycle lives in a single test so no other
    /// test can observe the process while `getppid` is redirected.
    @Test("applying and reverting redirects calls or reports the slot's TPRO denial")
    func applyRedirectsCallsAndRevertRestoresThem() throws {
        let requiresWritableTestImage = getenv("FRAMEWORK_TOOLBOX_REQUIRE_INTERPOSE_WRITES")
            .map { String(cString: $0) == "1" } ?? false
        let realParentProcessIdentifier = getppid()
        #expect(realParentProcessIdentifier != interposedParentProcessIdentifier)

        // Excluding the declaring image must leave this image alone — that is
        // what lets a replacement call the function it replaces.
        let exclusionReport = DyldDynamicInterpose.applyAll(
            to: .image(#dsohandle),
            excludingDeclaringImage: true
        )
        #expect(exclusionReport.rewrittenSlots.isEmpty)
        #expect(getppid() == realParentProcessIdentifier)

        let applyReport = DyldDynamicInterpose.applyAll(
            to: .image(#dsohandle),
            excludingDeclaringImage: false
        )
        defer { #expect(DyldDynamicInterpose.revertAll().skippedSlots.isEmpty) }

        // TPRO-protected GOT pages reject mprotect even when their maximum
        // protection includes writing. Only that observed restriction is an
        // expected failure; other permission errors must still fail this test.
        if !requiresWritableTestImage,
           !applyReport.skippedSlots.isEmpty,
           try applyReport.skippedSlots.allSatisfy({ slot in
               guard slot.reason == .memoryProtectionChangeFailed(errorNumber: EACCES) else {
                   return false
               }
               let region = try leafVMRegion(containing: slot.slotAddress)
               return region.flags & UInt16(VM_REGION_FLAG_TPRO_ENABLED) != 0
           }) {
            #expect(applyReport.rewrittenSlots.isEmpty)
            #expect(getppid() == realParentProcessIdentifier)
            #expect(DyldDynamicInterpose.revertAll().isEmpty)
            return
        }

        #expect(applyReport.skippedSlots.isEmpty)
        #expect(!applyReport.rewrittenSlots.isEmpty, "no symbol pointer slot matched getppid")
        #expect(getppid() == interposedParentProcessIdentifier)

        let revertReport = DyldDynamicInterpose.revertAll()
        #expect(revertReport.skippedSlots.isEmpty)
        #expect(revertReport.rewrittenSlots.count == applyReport.rewrittenSlots.count)
        #expect(getppid() == realParentProcessIdentifier)

        // Reverting twice is a no-op: the bookkeeping was consumed.
        #expect(DyldDynamicInterpose.revertAll().isEmpty)
    }

    @Test("an unmatched replacee rewrites nothing")
    func unrelatedReplaceeRewritesNothing() {
        let unmatchedAddress = UnsafeRawPointer(bitPattern: UInt(0xDEAD_0000_0000))!
        let report = DyldDynamicInterpose.apply(
            [DyldDynamicInterposeTuple(replacement: unmatchedAddress, replacee: unmatchedAddress)],
            to: .image(#dsohandle)
        )
        #expect(report.isEmpty)
    }
}

#endif
