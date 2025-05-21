{
  description = "A dev shell with MSan-enabled libc++";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib; # For lib.escapeShellArg if complex flags were needed, though not strictly for "-fsanitize=memory"

          llvmPkgs = pkgs.llvmPackages_latest;

          libcxx_msan = llvmPkgs.libcxx.overrideAttrs (oldAttrs: {
            pname = oldAttrs.pname + "-msan";

            stdenv = llvmPkgs.stdenv; # Ensures useLLVM context for underlying libcxx derivation

            buildInputs = (oldAttrs.buildInputs or []) ++ [ 
              llvmPkgs.compiler-rt 
              llvmPkgs.libunwind # Often needed by sanitizers
            ];

            # These ensure .o files are instrumented by the Nix compiler wrappers
            NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -fsanitize=memory -fno-omit-frame-pointer";
            NIX_CXX_FLAGS_COMPILE = (oldAttrs.NIX_CXX_FLAGS_COMPILE or "") + " -fsanitize=memory -fno-omit-frame-pointer";

            cmakeFlags = (oldAttrs.cmakeFlags or []) ++ [
              "-DLIBCXX_USE_SANITIZER=Memory"             # Primary switch for libcxx to enable MSan internally
              "-DLIBCXX_ENABLE_SHARED=OFF"                # Build libc++.a
              "-DLIBCXXABI_ENABLE_SHARED=OFF"             # Explicitly ensure libc++abi is not built as shared if possible
              "-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON"     # Ensures libc++abi.a is built

              "-DCMAKE_C_COMPILER=${llvmPkgs.clang}/bin/clang"
              "-DCMAKE_CXX_COMPILER=${llvmPkgs.clang}/bin/clang++"

              # Correct syntax for setting linker flags for CMake.
              # These flags are passed to the Clang driver when it performs linking.
              "-DCMAKE_EXE_LINKER_FLAGS:STRING=-fsanitize=memory"
              "-DCMAKE_SHARED_LINKER_FLAGS:STRING=-fsanitize=memory"
              "-DCMAKE_MODULE_LINKER_FLAGS:STRING=-fsanitize=memory"
            ];
            
            dontUseLTO = true; # LTO can interfere with sanitizers
          });

          clangInShell = llvmPkgs.clang;
        in
        {
          default = pkgs.mkShell {
            name = "msan-devshell";

            packages = [
              clangInShell
              libcxx_msan
              llvmPkgs.compiler-rt
              llvmPkgs.libunwind
              pkgs.gdb
            ];

            shellHook = ''
              export CC="${clangInShell}/bin/clang"
              export CXX="${clangInShell}/bin/clang++"

              echo "MSan Development Shell Initialized"
              echo "----------------------------------"
              echo "Custom MSan-enabled libc++ is available at: ${libcxx_msan}"
              echo "Clang compiler: $CXX (version $(${clangInShell}/bin/clang --version | head -n1))"
              echo "compiler-rt: ${llvmPkgs.compiler-rt}"
              echo "libunwind: ${llvmPkgs.libunwind}"
              echo ""
              echo "To compile 'your_program.cpp' with MemorySanitizer using this libc++:"
              echo ""
              echo "CXX_FLAGS=\"-fsanitize=memory -fno-omit-frame-pointer -std=c++17 -g\""
              echo "INCLUDE_FLAGS=\"-nostdinc++ -isystem ${libcxx_msan}/include/c++/v1\""
              echo "LINK_PATHS_STATIC_LIBCXX=\"-L${libcxx_msan}/lib ${libcxx_msan}/lib/libc++.a ${libcxx_msan}/lib/libc++abi.a\""
              echo "LINK_FLAGS_RUNTIME=\"-pthread -lm -ldl -rtlib=compiler-rt -lunwind\"" # -rtlib=compiler-rt is key for Clang to link its runtime
              echo ""
              echo "$CXX \$CXX_FLAGS \$INCLUDE_FLAGS \$LINK_PATHS_STATIC_LIBCXX your_program.cpp -o your_program \$LINK_FLAGS_RUNTIME"
              echo ""
            '';
          };
        }
      );
    };
}
