# CHAY — AI assistant for iOS

**English** · [Türkçe](README.tr.md)

A native iOS assistant that runs on **your own LLM API key**. It researches the web, reads your files, writes documents, remembers things about you, connects to MCP servers and works with any OpenAI-compatible endpoint. All agent logic runs on the phone; there is no backend server, and your data only goes to the providers and services you configure.

## Download

The latest version is **[v1.3](https://github.com/CagriKarakus/CHAY-IOS-CHATBOT/releases/latest)**. Download the `.ipa` from [Releases](https://github.com/CagriKarakus/CHAY-IOS-CHATBOT/releases) and install it with Sideloadly (see [Installing on an iPhone](#installing-on-an-iphone)). The app is not on the App Store.

| Version | Highlights |
| --- | --- |
| v1.3 | Connect services from the chat with a secure sign-in window, fallback models per provider, clearer tool errors the assistant can act on, fix for MCP servers using CRLF |
| v1.2 | Answers keep running in the background on iOS 26+, scheduled tasks (notification or Shortcuts automation), scheduled tasks in backups |
| v1.1 | Claude-style sidebar and chat menu (pin, rename, share, move to project), reply alternatives (‹ 1/2 ›), per-model token limits with a fallback model, MCP connectors with browser sign-in, keyless DuckDuckGo search |
| v1.0 | First stable build |

## Features

### Chat and models
- **Streaming chat** with any OpenAI-compatible `/chat/completions` endpoint, with the model's **reasoning** shown live and a collapsible tool log
- **Multiple providers and models**: presets for common routers and providers, model lists fetched from the server, a model picker in the chat screen and **reasoning effort** (low / medium / high)
- **Capabilities detected automatically** from `/models` when the server reports them (e.g. Evren `modalities`, OpenRouter `architecture`) and adjustable by hand
- **Images, audio and documents**: attach photos (or take them with the camera), voice recordings, PDF, Word, Excel, PowerPoint and text files; document text is extracted on the device, so it works with any model. Scanned PDFs are read with the phone's own text recognition, up to 30 scanned pages
- **Image generation** with models that support `/images/generations`, and **read aloud** with the phone's built-in voices
- **Edit and regenerate** messages, with the same or another model; earlier versions are kept and you can switch between them with ‹ 1/2 ›
- **Token limits**: set daily and monthly limits (input + output tokens) per model; when one is reached, requests go to a fallback model you chose until the limit resets, or you are asked to pick one
- **Fallback models**: give each provider an ordered list of backup models, including models from other providers. If it's overloaded, has a server problem or can't be reached, the reply continues on the next model and returns to the main model on your next message. You can also set a fallback by asking in the chat
- **Long chats**: old tool results are trimmed and older messages are summarized when the context gets large

### Tools
- **Web research** with the provider's own search where available (OpenRouter), or with Tavily, Brave Search, your own SearXNG, or **DuckDuckGo with no key**. If the Tavily or Brave key is missing, invalid or out of quota, searches fall back to DuckDuckGo automatically
- **Page and feed reading** (HTML, RSS, Atom) with sources cited in the reply
- **Calculator** evaluated by the phone's JavaScript engine after a strict allow-list check
- **Markdown documents** and **artifacts** (interactive HTML pages) that open in the app and show up in the Files app
- **Connectors (MCP)**: add remote MCP servers (Streamable HTTP) with no auth, an access token, or **sign in with the browser** (OAuth with discovery, dynamic client registration, PKCE and token refresh). Tools that may change data ask before each run unless you allow them; connectors and their tools can be turned on or off per chat
- **Connect from the chat**: ask "connect GitHub" and the assistant finds the address (checked list, then the official MCP registry, then the web) and opens a confirmation window. Tokens are typed only into that window and go straight to the Keychain, so the model never sees them; the new tools work in the same reply
- **Skills** in the Agent Skills format (`SKILL.md`), imported from any GitHub repository or written by you; the model loads a skill only when a task matches

### Organizing
- **Sidebar** like Claude's: swipe right anywhere on the chat or tap the menu button. It shows projects (each can be expanded to list its chats), documents, pinned chats and recent chats, with Settings and New chat at the bottom
- **Chat menu** (top-right, or long-press a chat in the sidebar): pin, share as Markdown or PDF, rename, add to a project, delete
- **Projects** that group chats with shared instructions and files
- **Search** across all chats, a **prompt library** for frequent requests
- **Incognito chats** that are not saved and don't touch memory; the incognito button is shown on a new chat

### Memory and personalization
- **Memory**: lasting facts and preferences are saved as notes and shared with every chat (Settings → Memory), with a per-chat memory switch
- **Personal instructions** added to every chat (e.g. "don't use emoji")
- **Appearance**: system, light or dark (Atom One palette)
- **English and Turkish** interface

### Everyday use
- **Shortcuts**: the *Ask CHAY* action sends a prompt (and files such as screenshots) with the model you choose, e.g. a daily news summary at 7:00
- **Scheduled tasks**: save prompts with a model, time and days; a notification at that time runs the task with one tap, or a Shortcuts automation with the *Run CHAY Task* action runs it fully automatically (the app shows the steps and opens Shortcuts)
- **Background handling**: on iOS 26 and later a reply keeps running after you leave the app, with progress shown by iOS; on older versions it continues for a while, resumes when you come back and sends a notification when it's ready
- **Usage**: token usage and tokens/second per reply, totals per provider and model, provider balance where available, search counts per service
- **Backup**: export everything to one file and import it back (API keys, tokens and sign-ins are never included)

## Security

- API keys, connector tokens and OAuth credentials are stored only in the Keychain (`WhenUnlockedThisDeviceOnly`) and never logged
- HTTPS only; no App Transport Security exceptions
- Connectors found by the assistant can't be added without your confirmation; addresses outside the checked list are marked unverified, and local network addresses are refused
- Web pages and connector results are passed to the model as clearly marked data with an instruction not to follow it
- After web content was read, saving to memory requires your approval; connector tools that may change data ask before running
- The file tools can only write plain names inside the app's Documents folder
- Each request is capped at a fixed number of model calls

## Architecture

| Folder | Contents | Built and tested on |
| --- | --- | --- |
| `Packages/AgentCore/` | LLM client (SSE), agent loop, tools, web search, MCP client and OAuth, context compaction. No Apple-only frameworks. | Windows (`swift test`) and CI |
| `App/` | SwiftUI, SwiftData, Keychain, App Intents and other iOS-specific code | CI (macOS) |
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
   CI builds are kept for 14 days. Stable versions are attached to [Releases](https://github.com/CagriKarakus/CHAY-IOS-CHATBOT/releases) and don't expire. To download the latest one (or name a version such as `v1.0`):
   ```powershell
   gh release download --repo CagriKarakus/CHAY-IOS-CHATBOT --pattern "*.ipa"
   ```
3. Install the `.ipa` with Sideloadly. Installing over the existing app keeps your settings and data. Before going back to an older version, export a backup first.
4. On first install, enable *Settings → Privacy & Security → Developer Mode* and trust the developer profile under *Settings → General → VPN & Device Management*.

With a free Apple account the signature lasts 7 days; reinstalling renews it. Features that need a paid developer account (iCloud sync, Share Extension) are not included.

### Checking an endpoint

```powershell
$env:LLM_BASE_URL = "https://<router>/v1"
$env:LLM_API_KEY  = "<api-key>"
powershell -ExecutionPolicy Bypass -File scripts\faz0.ps1 -Model "<model>"
```

## License

CHAY is released under the [Apache License 2.0](LICENSE). Third-party packages keep their own licenses; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

## Roadmap

- iCloud sync and Share Extension (need a paid developer account)
- Providers' built-in image generation, and web search for more providers
- Face ID lock
- On-device models
