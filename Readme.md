# OpenSuperWhisper

**New in this Fork: Support for NVIDIA Parakeet models**

OpenSuperWhisper is a macOS application that provides real-time audio transcription using Whisper and Parakeet MLX models. It offers a seamless way to record and transcribe audio with customizable settings and keyboard shortcuts.

<p align="center">
<img src="docs/image.png" width="400" /> <img src="docs/image_indicator.png" width="400" />
</p>

Free alternative to paid services like:
* https://tryvoiceink.com
* https://goodsnooze.gumroad.com/l/macwhisper
* and etc..

## Installation

```shell
brew update # Optional
brew install opensuperwhisper
```

Or from [github releases page](https://github.com/Starmel/OpenSuperWhisper/releases).

## Features

- 🎙️ Real-time audio recording and transcription
- ⌨️ Global keyboard shortcuts for quick recording (use ```cmd + ` ```)
- 🌍 Support for multiple languages with auto-detection (not tested, but probably works)
- 🔄 Optional translation to English (for better translation add initial prompt with english sentences)
- 💾 Local storage of recordings with transcriptions
- 🎛️ Advanced transcription settings (not tested)

## Requirements

- macOS (Apple Silicon/ARM64)

## Support

If you encounter any issues or have questions, please:
1. Check the existing issues in the repository
2. Create a new issue with detailed information about your problem
3. Include system information and logs when reporting bugs

# Building locally

To build locally, you'll need:

    git clone git@github.com:Starmel/OpenSuperWhisper.git
    cd OpenSuperWhisper
    git submodule update --init --recursive
    brew install cmake
    ./run.sh build

In case of problems, consult `.github/workflows/build.yml` which is our CI workflow
where the app gets built automatically on GitHub's CI.

## Contributing

Contributions are welcome! Please feel free to submit pull requests or create issues for bugs and feature requests.

### Contribution TODO list

- [ ] Streaming transcription ([#22](https://github.com/Starmel/OpenSuperWhisper/issues/22))
- [ ] Custom dictionary ([#20](https://github.com/Starmel/OpenSuperWhisper/issues/35))
- [ ] Intel macOS compatibility ([#16](https://github.com/Starmel/OpenSuperWhisper/issues/16))
- [ ] Agent mode ([#14](https://github.com/Starmel/OpenSuperWhisper/issues/14))
- [x] Background app ([#9](https://github.com/Starmel/OpenSuperWhisper/issues/9))
- [x] Support long-press single key audio recording ([#19](https://github.com/Starmel/OpenSuperWhisper/issues/19))

## License

OpenSuperWhisper is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Models

### Whisper Models

You can download Whisper model files (`.bin`) from the [Whisper.cpp Hugging Face repository](https://huggingface.co/ggerganov/whisper.cpp/tree/main). Place the downloaded `.bin` files in the app's models directory. On first launch, the app will attempt to copy a default model automatically, but you can add more models manually.

### Parakeet MLX Models

OpenSuperWhisper also supports Parakeet models optimized for Apple Silicon using MLX. The app includes built-in support for downloading Parakeet models directly from the interface, including:
- Parakeet-TDT-0.6B-v2 (English-focused)
- Parakeet-TDT-0.6B-v3 (Multilingual support)

You can also manually download Parakeet models from [Hugging Face MLX Community](https://huggingface.co/mlx-community) repositories.
