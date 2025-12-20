# External Integrations

**Analysis Date:** 2025-12-20

## APIs & External Services

**External APIs:**
- Not detected - No URLSession, HTTP client libraries, or REST API integration found

**External Services:**
- Not detected - No cloud services (Firebase, AWS, Azure, etc.) integration

**Third-party Dependencies:**
- Not detected - Zero external package dependencies

## Data Storage

**Databases:**
- Not applicable - No database used

**File Storage:**
- Local file system only
- Security-scoped bookmarks for persistent folder access - `DatasetViewModel.swift:39-72`
- FileManager API for directory scanning - `DatasetViewModel.swift:118, 144, 169`
- Supported image formats: jpg, jpeg, png, webp, bmp, tiff - `DatasetViewModel.swift:14`
- Supported caption formats: txt, caption - `DatasetViewModel.swift:15`

**Caching:**
- Not applicable - No caching layer

## Authentication & Identity

**Auth Provider:**
- macOS App Sandbox - `lora_dataset.entitlements`
- Security-scoped bookmarks for file access - `DatasetViewModel.swift:39-72, 102-113`
- No user authentication required

**OAuth Integrations:**
- Not applicable

## Monitoring & Observability

**Error Tracking:**
- Console logging only (print statements in DEBUG mode)
- No external error tracking service

**Analytics:**
- Not applicable

**Logs:**
- Console output only - `lora_datasetApp.swift` (suppresses system logs in DEBUG)
- File operation logging in `DatasetViewModel.swift` with `[saveSelected]` prefix

## CI/CD & Deployment

**Hosting:**
- Standalone macOS application
- No cloud hosting

**CI Pipeline:**
- Not detected - No GitHub Actions, CI configuration files found

## Environment Configuration

**Development:**
- No environment variables required
- Configuration stored in UserDefaults - `DatasetViewModel.swift:44, 80`
- App entitlements configure sandbox permissions

**Production:**
- Same as development
- Security-scoped bookmarks persist user folder access across launches

## File System Interactions

**Folder Selection:**
- NSOpenPanel for folder picker - `DatasetViewModel.swift:29-35`
- Creates security-scoped bookmarks for persistent access - `DatasetViewModel.swift:39-42`
- Stores bookmarks in UserDefaults with key "securedDirectoryBookmark"

**Directory Scanning:**
- Recursive file enumeration - `DatasetViewModel.swift:118`
- Matches images with caption files by basename - `DatasetViewModel.swift:134-141`
- Supported patterns: `{image-basename}.txt` or `{image-basename}.caption`

**File Operations:**
- Read captions: `String(contentsOf:)` - `DatasetViewModel.swift:145, 192`
- Write captions: `write(to:atomically:encoding:)` - `DatasetViewModel.swift:173-175`
- All operations wrapped in security-scoped access - `DatasetViewModel.swift:101-113, 166`

## Webhooks & Callbacks

**Incoming:**
- Not applicable

**Outgoing:**
- Not applicable

---

*Integration audit: 2025-12-20*
*Update when adding/removing external services*
