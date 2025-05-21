{
  description = "tsandrini: nix devshell for MSan-enabled libc++";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    systems.url = "github:nix-systems/default";
  };

  outputs = { self, nixpkgs, systems }:
    let
      supportedSystems = import systems;
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          # TODO: change to your preffered llvm version
          llvmPkgs = pkgs.llvmPackages_latest;

          libcxx_msan = llvmPkgs.libcxx.overrideAttrs (oldAttrs: {
            pname = oldAttrs.pname + "-msan";
            stdenv = llvmPkgs.stdenv; 

            buildInputs = (oldAttrs.buildInputs or []) ++ [ 
              llvmPkgs.compiler-rt 
              llvmPkgs.libunwind # needed by sanitizers
            ];

            # ensure .o files are instrumented by the Nix compiler wrappers
            NIX_CFLAGS_COMPILE = (oldAttrs.NIX_CFLAGS_COMPILE or "") + " -fsanitize=memory -fno-omit-frame-pointer";
            NIX_CXX_FLAGS_COMPILE = (oldAttrs.NIX_CXX_FLAGS_COMPILE or "") + " -fsanitize=memory -fno-omit-frame-pointer";

            cmakeFlags = (oldAttrs.cmakeFlags or []) ++ [
              "-DLIBCXX_USE_SANITIZER=Memory"             # primary switch for libcxx to enable MSan internally
              "-DLIBCXX_ENABLE_SHARED=OFF"                # build libc++.a
              "-DLIBCXXABI_ENABLE_SHARED=OFF"             # explicitly ensure libc++abi is not built as shared if possible
              "-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON"     # ensures libc++abi.a is built

              "-DCMAKE_C_COMPILER=${llvmPkgs.clang}/bin/clang"
              "-DCMAKE_CXX_COMPILER=${llvmPkgs.clang}/bin/clang++"

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
