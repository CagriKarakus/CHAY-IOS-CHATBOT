# AI Assistant for iOS

**English** · [Türkçe](README.tr.md)

A native iOS assistant that runs on **your own LLM API key**. It can research the web, write Markdown documents, remember things about you and work with any OpenAI-compatible endpoint. All agent logic runs on the phone; there is no backend server and your data only goes to the providers you configure.

## Features

- **Streaming chat** with any OpenAI-compatible `/chat/completions` endpoint
- **Multiple providers and models**: add several endpoints (base URL + key) with any number of models each, fetch the model list from the server, and switch models from the chat screen
- **Reasoning effort** (low / medium / high) for models that support `reasoning_effort`
- **Web research** with [Tavily](https://tavily.com): the model decides how many searches and results a question needs, reads pages and cites sources
- **Markdown documents**: the assistant writes `.md` files that show up in the Files app; view and share them in the app
- **Memory**: lasting facts and preferences are saved as notes and shared with every chat; notes can be edited or deleted
- **Personal instructions** added to every chat (e.g. "don't use emoji")
- **Saved chats**, readable network errors with *Try again*, and finishing a reply in the background
- **Control and transparency**: stop button, collapsible tool log, token usage and tokens/second per reply, usage totals per provider and model, Tavily search count
- **Long chats**: old tool results are trimmed and older messages are summarized when the context gets large
- **English and Turkish** interface
- Atom One Dark theme

## Security

- API keys are stored only in the Keychain (`WhenUnlockedThisDeviceOnly`) and never logged
- HTTPS only; no App Transport Security exceptions
- Web content is passed to the model as clearly marked data with an instruction not to follow it
- After web content was read, saving to memory requires your approval
- The file tool can only write plain `.md` names inside the app's Documents folder
- Each request is capped at a fixed number of model calls

## Architecture

| Folder | Contents | Built and tested on |
| --- | --- | --- |
| `Packages/AgentCore/` | LLM client (SSE), agent loop, tools, context compaction. No Apple-only frameworks. | Windows (`swift test`) and CI |
| `App/` | SwiftUI, SwiftData, Keychain and other iOS-specific code | CI (macOS) |
| `project.yml` | [XcodeGen](https://github.com/yonaskolb/XcodeGen) project definition (the `.xcodeproj` is not committed) | CI |
| `.github/workflows/ios.yml` | Tests and an unsigned `.ipa` build | GitHub Actions |
| `scripts/faz0.ps1` | Checks an endpoint for streaming and tool calling and records SSE fixtures | Windows |

## Development without a Mac

The project is developed on Windows. Logic lives in `AgentCore` and is tested locally; the iOS app is built by GitHub Actions on macOS and sideloaded.

1. Install **Git** and the **GitHub CLI**, then run `gh auth login`.
2. Install **Visual Studio Build Tools** with *MSVC x64/x86* and the *Windows 11 SDK*, then the **Swift toolchain**:
   ```powershell
   winget install --id Swift.Toolchain
   ```
3. Run the tests:
   ```powershell
   swift test --package-path Packages/AgentCore
   ```
4. Install **iTunes** (from apple.com, not the Microsoft Store) and **Sideloadly**. Use a separate Apple ID for development.

### Installing on an iPhone

1. Push to `main` (or run the *iOS* workflow manually).
2. Download the build:
   ```powershell
   gh run download <run-id> --name AIAssistant-ipa
   ```
3. Install `AIAssistant.ipa` with Sideloadly. Installing over the existing app keeps your settings and data.
4. On first install, enable *Settings → Privacy & Security → Developer Mode* and trust the developer profile under *Settings → General → VPN & Device Management*.

With a free Apple account the signature lasts 7 days; reinstalling renews it.

### Checking an endpoint

```powershell
$env:LLM_BASE_URL = "https://<router>/v1"
$env:LLM_API_KEY  = "<api-key>"
powershell -ExecutionPolicy Bypass -File scripts\faz0.ps1 -Model "<model>"
```

## Roadmap

- Image and audio input, spoken replies and image generation for models that support them
- Share Extension, Face ID lock, PDF input, voice input
- Siri / Shortcuts, remote MCP servers, on-device models, iCloud sync
