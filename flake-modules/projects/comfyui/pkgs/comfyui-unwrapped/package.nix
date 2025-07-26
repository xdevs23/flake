{ lib
, fetchFromGitHub
, fetchurl
, python3Packages
, python3
, withXpu ? false
}:
let
  spandrel = python3Packages.callPackage ../../../../packages/spandrel/default.nix {};
  
  # Use existing torch from nixpkgs but override src to XPU wheel when needed
  torchPackages = if withXpu then (
    let
      pyVer = "cp${lib.replaceStrings ["."] [""] python3.pythonVersion}";
      platform = if lib.hasInfix "linux" python3.stdenv.hostPlatform.system then "linux_x86_64" else "win_amd64";
      manylinuxPlatform = if lib.hasInfix "linux" python3.stdenv.hostPlatform.system then "manylinux_2_28_x86_64" else "win_amd64";
    in {
      torch = python3Packages.torch.overrideAttrs (oldAttrs: rec {
        version = "2.9.0.dev20250726+xpu";
        format = "wheel";
        src = fetchurl {
          url = "https://download.pytorch.org/whl/nightly/xpu/torch-${lib.replaceStrings ["+"] ["%2B"] version}-${pyVer}-${pyVer}-${platform}.whl";
          hash = "sha256-qtmCRz753pJZ3cuDOOAAJVZ94L085gn5zH0Aplt6cC0=";
        };
        # Skip build phases since it's a wheel
        dontBuild = true;
        dontConfigure = true;
        # Disable import checks to avoid MPI issues during build
        pythonImportsCheck = [ ];
        doCheck = false;
        # Remove build inputs that aren't needed for wheels
        nativeBuildInputs = [ ];
        buildInputs = [ ];
      });
      
      torchvision = python3Packages.torchvision.overrideAttrs (oldAttrs: rec {
        version = "0.24.0.dev20250726+xpu";
        format = "wheel";
        src = fetchurl {
          url = "https://download.pytorch.org/whl/nightly/xpu/torchvision-${lib.replaceStrings ["+"] ["%2B"] version}-${pyVer}-${pyVer}-${manylinuxPlatform}.whl";
          hash = "sha256-ivpudeUKhOD7OXFoOVYUnYQGj0BPazy1gahkS8/2yjc=";
        };
        dontBuild = true;
        dontConfigure = true;
        pythonImportsCheck = [ ];
        doCheck = false;
        nativeBuildInputs = [ ];
        buildInputs = [ ];
        # Update dependencies to use XPU torch (using new dependencies format)
        dependencies = [ torchPackages.torch ] ++ (builtins.filter (dep: dep != python3Packages.torch) (oldAttrs.dependencies or [ ]));
      });
      
      torchaudio = python3Packages.torchaudio.overrideAttrs (oldAttrs: rec {
        version = "2.8.0.dev20250726+xpu";
        format = "wheel";
        src = fetchurl {
          url = "https://download.pytorch.org/whl/nightly/xpu/torchaudio-${lib.replaceStrings ["+"] ["%2B"] version}-${pyVer}-${pyVer}-${manylinuxPlatform}.whl";
          hash = "sha256-Fogn36XmXtB5sz2UuPdMVmHkoqc5Kuvtyig8J/uVigA=";
        };
        dontBuild = true;
        dontConfigure = true;
        pythonImportsCheck = [ ];
        doCheck = false;
        nativeBuildInputs = [ ];
        buildInputs = [ ];
        dependencies = [ torchPackages.torch ] ++ (builtins.filter (dep: dep != python3Packages.torch) (oldAttrs.dependencies or [ ]));
      });
    }
  ) else {
    torch = python3Packages.torch;
    torchvision = python3Packages.torchvision;
    torchaudio = python3Packages.torchaudio;
  };
in
python3Packages.buildPythonApplication rec {
  pname = "comfyui";
  version = "0.3.9";

  src = fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    rev = "v${version}";
    hash = "sha256-3D3Xk7yDesAjHIgBBCHOQFGt1HsGVBSXUi6zsW1dgcs=";
  };

  dependencies = with python3Packages; [
    torchPackages.torch
    (if withXpu then 
      torchsde.override { 
        torch = torchPackages.torch; 
      } 
      else torchsde)
    torchPackages.torchvision
    torchPackages.torchaudio
    einops
    transformers
    tokenizers
    sentencepiece
    safetensors
    aiohttp
    pyyaml
    pillow
    scipy
    tqdm
    psutil

    # optional dependencies  
    (if withXpu then 
      kornia.override { 
        torch = torchPackages.torch; 
      }
      else kornia)
    spandrel
    soundfile
  ];

  # Disable import checks for the whole package when using XPU
  pythonImportsCheck = if withXpu then [ ] else [ "comfy" ];
  doCheck = if withXpu then false else true;

  format = "other";

  buildPhase = "true";

  installPhase = ''
    mkdir -p $out/${python3.sitePackages}
    cp -r * $out/${python3.sitePackages}
  '';

  postPatch = ''
     substituteInPlace folder_paths.py \
       --replace-fail "os.path.dirname(os.path.realpath(__file__))" 'os.path.join(os.getenv("XDG_DATA_HOME", os.path.join(os.path.expanduser("~"), ".local", "share")), "comfyui")'
  '';

  nativeBuildInputs = [ python3 ];

  postFixup = ''
    chmod +x $out/${python3.sitePackages}/main.py
    sed -i -e '1i#!/usr/bin/python' $out/lib/python3*/site-packages/main.py
    patchShebangs $out/${python3.sitePackages}/main.py

    mkdir $out/bin
    ln -s $out/lib/python3*/site-packages/main.py $out/bin/comfyui

    wrapProgram "$out/bin/comfyui" \
      --prefix PYTHONPATH : "$PYTHONPATH" \
  '';

  meta = with lib; {
    description = "The most powerful and modular stable diffusion GUI with a graph/nodes interface";
    homepage = "https://github.com/comfyanonymous/ComfyUI";
    license = licenses.gpl3Only;
    mainProgram = "comfyui";
    platforms = platforms.all;
  };
}
