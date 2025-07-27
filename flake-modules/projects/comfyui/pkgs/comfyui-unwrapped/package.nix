{ lib
, fetchFromGitHub
, fetchurl
, python3Packages
, python3
, withXpu ? false
}:
let
  spandrel = python3Packages.callPackage ../../../../packages/spandrel/default.nix {};
  
  # Use existing torch from nixpkgs but override src to latest commits when XPU needed
  torchPackages = if withXpu then (
    let
      torchSrc = fetchFromGitHub {
        owner = "pytorch";
        repo = "pytorch";
        rev = "f6761f2968ca4e8ca1c6fbe4771c804a8bdcafb6";
        hash = "sha256-dryQ1I4RemvdCdC9Qu5i6ZTeeTHtmBjfMYN4NG5+TVA=";
        fetchSubmodules = true;
      };
      
      torchvisionSrc = fetchFromGitHub {
        owner = "pytorch";
        repo = "vision";
        rev = "b818d320a14a2e6d9d9f28853e9e7beae703e52e";
        hash = "sha256-WtX9t3XrXP0pJI1i2yOH/MtPbpdGue8YddenfFrlxQM=";
      };
      
      torchaudioSrc = fetchFromGitHub {
        owner = "pytorch";
        repo = "audio";
        rev = "f6dfe1231dcdd221a68416e49ab85c2575cbb824";
        hash = "sha256-0ASFFSbIGbBmdVMhQ6zGNXLZRxl7kbWrPX16VcfEkts=";
        fetchSubmodules = true;
      };
    in {
      torch = python3Packages.torch.overrideAttrs (oldAttrs: rec {
        version = "2.9.0-dev+xpu";
        src = torchSrc;
      });
      
      torchvision = python3Packages.torchvision.overrideAttrs (oldAttrs: rec {
        version = "0.24.0-dev+xpu";
        src = torchvisionSrc;
        dependencies = [ torchPackages.torch ] ++ (builtins.filter (dep: dep != python3Packages.torch) (oldAttrs.dependencies or [ ]));
      });
      
      torchaudio = python3Packages.torchaudio.overrideAttrs (oldAttrs: rec {
        version = "2.8.0-dev+xpu";
        src = torchaudioSrc;
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
