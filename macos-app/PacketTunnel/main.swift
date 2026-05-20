import Darwin
import Foundation

@_silgen_name("NSExtensionMain")
private func NSExtensionMain(
    _ argc: Int32,
    _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
) -> Int32

exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
