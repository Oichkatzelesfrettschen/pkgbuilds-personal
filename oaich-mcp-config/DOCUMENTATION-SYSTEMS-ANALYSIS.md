# Documentation Systems Analysis
# For MCP Configuration and Technical Projects
# Date: 2025-10-30
# Based on October 2025 research

---

## Executive Summary

Analysis of modern documentation generation systems for technical projects, specifically for documenting the Oaich-mcp-config setup, MCP server implementations, and other CachyOS/Arch Linux projects.

**Recommended Stack:**
1. **MkDocs + Material Theme** - General documentation, user guides
2. **Sphinx + Breathe + Doxygen** - C/C++ API documentation
3. **Sphinx (Python)** - Python MCP server documentation
4. **TypeDoc** - TypeScript MCP server documentation

---

## MCP Architecture (Researched 2025-10-30)

### Protocol Overview

**Standard:** Model Context Protocol (MCP)
**Introduced:** November 2024 by Anthropic
**Specification:** JSON-RPC 2.0 over stdio or HTTP
**Latest Version:** 2025-06-18

### Architecture Components

```
┌─────────────────┐         JSON-RPC 2.0         ┌──────────────────┐
│   MCP Client    │◄──────────────────────────►│   MCP Server     │
│  (Claude Code)  │    stdio / HTTP / SSE       │  (Python/TS/Go)  │
└─────────────────┘                             └──────────────────┘
         │                                               │
         │                                               │
         ▼                                               ▼
   ┌──────────┐                                  ┌─────────────┐
   │  Roots   │                                  │  Prompts    │
   │ Sampling │                                  │  Resources  │
   └──────────┘                                  │  Tools      │
                                                 └─────────────┘
```

### Key Primitives

**Server Capabilities:**
1. **Prompts** - Instruction templates for LLMs
2. **Resources** - Structured data for context
3. **Tools** - Executable functions LLMs can call

**Client Capabilities:**
1. **Roots** - Directory/workspace specifications
2. **Sampling** - LLM invocation from servers

### Transport Mechanisms
- **stdio** - Standard input/output (most common)
- **HTTP** - RESTful, stateless (new in 2025-03-26)
- **SSE** - Server-Sent Events (deprecated, use HTTP)

### JSON-RPC Message Flow

```json
// Client Request
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "filesystem_read",
    "arguments": {
      "path": "~/example.txt"
    }
  }
}

// Server Response
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "File contents here..."
      }
    ]
  }
}
```

---

## MCP Server Implementation Best Practices

### Python SDK (2025)

**Official Package:** `mcp` (PyPI)
**Installation:** `pip install mcp` or `uvx mcp-server-<name>`
**Python Version:** >=3.10

**Framework Options:**

1. **Official MCP SDK** (mcp)
   - Full protocol compliance
   - Type hints with Pydantic
   - Resource, prompt, and tool decorators
   - Built-in logging and error handling

2. **FastMCP** (now part of official SDK)
   - Minimal boilerplate
   - Pythonic API
   - Rapid prototyping
   - Example: [Official Python SDK](https://github.com/modelcontextprotocol/python-sdk)

**Example Server:**

```python
from mcp.server import Server
from mcp.types import Resource, Tool

app = Server("my-server")

@app.list_resources()
async def list_resources():
    return [
        Resource(
            uri="file:///data.txt",
            name="My Data",
            mimeType="text/plain"
        )
    ]

@app.read_resource()
async def read_resource(uri: str):
    # Read and return resource content
    pass

@app.list_tools()
async def list_tools():
    return [
        Tool(
            name="process_data",
            description="Process data with specific parameters",
            inputSchema={
                "type": "object",
                "properties": {
                    "input": {"type": "string"}
                }
            }
        )
    ]

@app.call_tool()
async def call_tool(name: str, arguments: dict):
    if name == "process_data":
        # Execute tool logic
        return {"result": "processed"}
```

### TypeScript SDK (2025)

**Official Package:** `@modelcontextprotocol/sdk` (npm)
**Installation:** `npm install @modelcontextprotocol/sdk`
**TypeScript Version:** >=4.9

**Framework Options:**

1. **Official TypeScript SDK**
   - Full MCP specification
   - Type safety via Zod schemas
   - Transport abstraction
   - Example: [TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)

2. **EasyMCP**
   - Minimal boilerplate
   - Developer experience focused
   - Quick prototyping

3. **FastMCP (TypeScript)**
   - Built on official SDK
   - Rapid development
   - Low-level abstraction

**Example Server:**

```typescript
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

const server = new Server(
  {
    name: "my-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      resources: {},
      tools: {},
      prompts: {},
    },
  }
);

// Register tool
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "process_data",
        description: "Process data with parameters",
        inputSchema: {
          type: "object",
          properties: {
            input: { type: "string" },
          },
        },
      },
    ],
  };
});

// Start server
const transport = new StdioServerTransport();
await server.connect(transport);
```

### Best Practices (2025)

**Tool Design:**
- Model-controlled: AI decides which tools to call
- Clear names: Use descriptive, action-oriented names
- Schema validation: Enforce input schemas rigorously
- Error handling: Return meaningful error messages

**Resource Design:**
- Stable URIs: Use consistent, predictable URI schemes
- MIME types: Always specify correct MIME types
- Caching: Implement caching for expensive resources
- Pagination: Support pagination for large datasets

**Security:**
- Authentication: Implement OAuth 2.0 where appropriate
- Authorization: Check permissions before tool execution
- Input sanitization: Validate and sanitize all inputs
- Rate limiting: Prevent abuse with rate limits

**Performance:**
- Async operations: Use async/await throughout
- Connection pooling: Reuse connections where possible
- Lazy loading: Load resources only when needed
- Streaming: Stream large responses when possible

**Testing:**
- Unit tests: Test tools, resources, prompts individually
- Integration tests: Test full MCP message flows
- Mock clients: Use MCP inspector for testing
- Error scenarios: Test failure modes explicitly

---

## Documentation Generation Systems

### 1. MkDocs + Material Theme

**Best For:** User guides, tutorials, general documentation
**Language:** Python (Markdown source)
**Output:** Static HTML site
**Popularity:** Very High (10,000+ stars on GitHub)

#### Features

**Core MkDocs:**
- Markdown-based content
- Live preview server
- Full-text search
- Multi-language support (60+ languages)
- Theme system

**Material Theme Additions:**
- Modern, responsive design
- 10,000+ icons and emojis
- Built-in search with better UX
- Social media preview cards
- Code highlighting with 50+ languages
- Tabbed content, admonitions, annotations
- Version switcher
- Dark/light mode toggle

#### Installation

```bash
# With pip
pip install mkdocs-material

# With uv (recommended for CachyOS)
uv pip install mkdocs-material

# With pacman (if packaged)
sudo pacman -S mkdocs python-mkdocs-material
```

#### Configuration

```yaml
# mkdocs.yml
site_name: Oaich MCP Configuration
site_description: Model Context Protocol setup for CachyOS
site_author: Oaich
repo_url: https://github.com/yourusername/Oaich-mcp-config

theme:
  name: material
  palette:
    # Light mode
    - scheme: default
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-7
        name: Switch to dark mode
    # Dark mode
    - scheme: slate
      primary: indigo
      accent: indigo
      toggle:
        icon: material/brightness-4
        name: Switch to light mode
  features:
    - navigation.instant      # Instant loading
    - navigation.tracking     # URL updates with scroll
    - navigation.tabs         # Top-level tabs
    - navigation.sections     # Section index pages
    - navigation.expand       # Expand sections by default
    - navigation.top          # Back to top button
    - search.suggest          # Search suggestions
    - search.highlight        # Highlight search terms
    - content.code.copy       # Copy code button
    - content.tabs.link       # Link tabbed content

plugins:
  - search
  - social                    # Social cards
  - tags                      # Tag support

markdown_extensions:
  - pymdownx.highlight:
      anchor_linenums: true
  - pymdownx.superfences
  - pymdownx.tabbed:
      alternate_style: true
  - admonition
  - pymdownx.details
  - attr_list
  - md_in_html

nav:
  - Home: index.md
  - Getting Started:
    - Installation: getting-started/installation.md
    - Configuration: getting-started/configuration.md
  - MCP Servers:
    - Overview: servers/overview.md
    - Core Servers: servers/core.md
    - Development Servers: servers/development.md
  - Advanced:
    - Custom Servers: advanced/custom-servers.md
    - Troubleshooting: advanced/troubleshooting.md
  - Reference:
    - API: reference/api.md
```

#### Example Content

```markdown
# Installation

## Prerequisites

!!! info "System Requirements"
    - CachyOS (Arch Linux) x86-64-v3
    - Python >= 3.10
    - Node.js >= 18
    - uv package manager

## Installation Steps

=== "Quick Install"

    ```bash
    # Install package
    sudo pacman -S Oaich-mcp-config

    # Run installer
    /usr/share/Oaich-mcp-config/install-mcp-servers.sh
    ```

=== "Manual Install"

    ```bash
    # Install dependencies
    sudo pacman -S nodejs python uv git sqlite

    # Configure servers manually
    claude mcp add --transport stdio filesystem ...
    ```

!!! warning "Important"
    Make sure `uv` is installed for Python MCP servers!

## Verification

Check installation status:

```bash
claude mcp list
```

Expected output:

```
✓ filesystem: Connected
✓ memory: Connected
...
```
```

#### Building Documentation

```bash
# Serve locally with live reload
mkdocs serve

# Build static site
mkdocs build

# Deploy to GitHub Pages
mkdocs gh-deploy
```

#### Advantages

✅ Beautiful out of the box
✅ No HTML/CSS/JavaScript knowledge needed
✅ Live preview during development
✅ Excellent search functionality
✅ Mobile-responsive by default
✅ 60+ language translations
✅ Active development and community
✅ Extensive plugin ecosystem

#### Disadvantages

❌ Python dependency (but we already have Python)
❌ Limited customization without HTML/CSS
❌ Not ideal for API documentation
❌ Requires build step for deployment

---

### 2. Sphinx + Breathe + Doxygen (C/C++)

**Best For:** C/C++ API documentation from source code
**Language:** Python (Sphinx) + C/C++ (Doxygen)
**Output:** HTML, PDF, LaTeX, man pages
**Complexity:** High (but powerful)

#### Architecture

```
C/C++ Source Code
      ↓
   Doxygen (parses code comments)
      ↓
    XML Output
      ↓
   Breathe (Sphinx extension)
      ↓
 Sphinx Documentation
      ↓
 HTML / PDF / LaTeX / man pages
```

#### Installation

```bash
# Install Sphinx
pip install sphinx sphinx-rtd-theme

# Install Breathe (Doxygen bridge)
pip install breathe

# Install Doxygen (from repos)
sudo pacman -S doxygen

# Or with uv
uv pip install sphinx sphinx-rtd-theme breathe
```

#### Doxygen Configuration

```bash
# Generate Doxyfile
doxygen -g Doxyfile

# Edit Doxyfile
# Key settings:
# GENERATE_XML = YES
# XML_OUTPUT = xml
# INPUT = src/ include/
# RECURSIVE = YES
# EXTRACT_ALL = YES
# GENERATE_HTML = NO (Sphinx will generate HTML)
```

#### Sphinx Configuration

```python
# conf.py
import os
import sys

project = 'My C++ Library'
copyright = '2025, Oaich'
author = 'Oaich'

extensions = [
    'breathe',
    'sphinx.ext.autodoc',
    'sphinx.ext.intersphinx',
    'sphinx.ext.viewcode',
]

# Breathe configuration
breathe_projects = {
    "MyCppLib": "./doxygen/xml"
}
breathe_default_project = "MyCppLib"

# Theme
html_theme = 'sphinx_rtd_theme'
```

#### Building Documentation

```bash
# Run Doxygen first
doxygen Doxyfile

# Then Sphinx
sphinx-build -b html source build/html

# Or use Makefile
make html
```

#### Example C++ Documentation

```cpp
/**
 * @brief Calculate the factorial of a number
 *
 * This function computes n! using recursion.
 *
 * @param n The input number
 * @return The factorial of n
 * @throws std::invalid_argument if n < 0
 *
 * @code
 * int result = factorial(5);  // Returns 120
 * @endcode
 *
 * @note This is a recursive implementation
 * @warning Not optimized for large values of n
 *
 * @see iterative_factorial for an alternative
 */
int factorial(int n);
```

#### Example RST Documentation

```rst
API Reference
=============

Core Functions
--------------

.. doxygenfunction:: factorial
   :project: MyCppLib

.. doxygenclass:: MyClass
   :project: MyCppLib
   :members:
   :private-members:
```

#### Advantages

✅ Automated API documentation from code
✅ Multiple output formats (HTML, PDF, man)
✅ Cross-references between code and docs
✅ Excellent for large C/C++ projects
✅ Industry standard for C/C++ docs
✅ Integrates with Read the Docs

#### Disadvantages

❌ Complex setup (three tools to configure)
❌ Steep learning curve
❌ Requires detailed code comments
❌ Build process can be slow for large projects
❌ RST syntax less intuitive than Markdown

---

### 3. Sphinx (Python)

**Best For:** Python API documentation, Python MCP servers
**Language:** Python (reStructuredText or MyST Markdown)
**Output:** HTML, PDF, LaTeX, man pages, ePub

#### Features

- **autodoc:** Automatic documentation from docstrings
- **autosummary:** Generate summary tables
- **napoleon:** Support for Google/NumPy docstring styles
- **intersphinx:** Link to other Sphinx documentation
- **viewcode:** Link to highlighted source code

#### Installation

```bash
pip install sphinx sphinx-rtd-theme sphinx-autodoc-typehints myst-parser
```

#### Configuration

```python
# conf.py
extensions = [
    'sphinx.ext.autodoc',
    'sphinx.ext.autosummary',
    'sphinx.ext.napoleon',
    'sphinx.ext.intersphinx',
    'sphinx.ext.viewcode',
    'sphinx_autodoc_typehints',
    'myst_parser',  # For Markdown support
]

autosummary_generate = True
autodoc_typehints = 'description'
napoleon_google_docstring = True
napoleon_numpy_docstring = True

html_theme = 'sphinx_rtd_theme'
```

#### Example Python Documentation

```python
def read_file(path: str, offset: int = 0, length: int | None = None) -> str:
    """Read a file with optional offset and length.

    Args:
        path: Absolute path to the file
        offset: Line offset to start reading from (default: 0)
            - Positive: Start from line N
            - Negative: Read last N lines
        length: Maximum number of lines to read (default: None = all)

    Returns:
        The file contents as a string

    Raises:
        FileNotFoundError: If the file doesn't exist
        PermissionError: If the file can't be read

    Examples:
        >>> read_file("/tmp/test.txt")
        "Hello, World!"

        >>> read_file("/tmp/test.txt", offset=-10)
        "Last 10 lines..."

    Note:
        This function is optimized for text files. Binary files
        should use `read_binary()` instead.
    """
    ...
```

#### Building Documentation

```bash
# Generate API docs
sphinx-apidoc -o docs/source mypackage

# Build HTML
sphinx-build -b html docs/source docs/build/html

# Or use Makefile
make html
```

#### Advantages

✅ Automatic documentation from docstrings
✅ Type hint support
✅ Multiple docstring styles (Google, NumPy)
✅ Markdown support (via myst-parser)
✅ Excellent cross-referencing
✅ Industry standard for Python

#### Disadvantages

❌ RST syntax can be verbose
❌ Requires well-documented code
❌ Markdown support is secondary
❌ Theme customization can be complex

---

### 4. TypeDoc (TypeScript)

**Best For:** TypeScript MCP server documentation
**Language:** TypeScript
**Output:** HTML, JSON
**Simplicity:** High

#### Installation

```bash
npm install --save-dev typedoc
```

#### Configuration

```json
// typedoc.json
{
  "entryPoints": ["src/index.ts"],
  "out": "docs",
  "excludePrivate": true,
  "excludeProtected": false,
  "excludeInternal": true,
  "readme": "README.md",
  "theme": "default",
  "name": "My MCP Server",
  "includeVersion": true
}
```

#### Example TypeScript Documentation

```typescript
/**
 * Read a file from the filesystem
 *
 * @param path - Absolute path to the file
 * @param options - Read options
 * @returns Promise resolving to file contents
 * @throws {FileNotFoundError} If file doesn't exist
 *
 * @example
 * ```ts
 * const content = await readFile("/tmp/test.txt", {
 *   offset: 0,
 *   length: 100
 * });
 * ```
 *
 * @remarks
 * This function is optimized for text files.
 *
 * @see {@link readBinary} for binary files
 */
export async function readFile(
  path: string,
  options?: ReadOptions
): Promise<string> {
  // Implementation
}

/**
 * Options for reading files
 */
export interface ReadOptions {
  /** Line offset to start from */
  offset?: number;

  /** Maximum lines to read */
  length?: number;

  /** File encoding (default: 'utf8') */
  encoding?: BufferEncoding;
}
```

#### Building Documentation

```bash
# Generate docs
npx typedoc

# With custom config
npx typedoc --options typedoc.json
```

#### Advantages

✅ Zero configuration needed
✅ Type information automatically included
✅ Clean, modern UI
✅ Excellent TypeScript integration
✅ JSON output for custom processing
✅ Fast generation

#### Disadvantages

❌ TypeScript-only (no JavaScript support)
❌ Limited theme options
❌ Less customization than Sphinx
❌ No Markdown in comments (only JSDoc)

---

## Recommendations for Oaich Projects

### For Oaich-mcp-config

**Primary:** MkDocs + Material Theme

**Rationale:**
- ✅ User-focused documentation (installation, guides)
- ✅ Beautiful, responsive design
- ✅ Easy to maintain (Markdown)
- ✅ No programming needed for content
- ✅ Excellent search
- ✅ Dark mode support
- ✅ Already have Python installed

**Structure:**
```
docs/
├── index.md                  # Home page
├── getting-started/
│   ├── installation.md       # Installation guide
│   ├── configuration.md      # Configuration guide
│   └── verification.md       # Verification steps
├── servers/
│   ├── overview.md           # Server overview
│   ├── core.md               # Core servers
│   ├── posix.md              # POSIX/shell servers
│   ├── development.md        # Dev servers
│   └── browser.md            # Browser automation
├── advanced/
│   ├── custom-servers.md     # Creating custom servers
│   ├── posix-compliance.md   # POSIX compliance guide
│   └── troubleshooting.md    # Troubleshooting guide
├── reference/
│   ├── commands.md           # Command reference
│   ├── configuration.md      # Config file reference
│   └── api.md                # API reference
└── mkdocs.yml
```

### For Python MCP Servers

**Primary:** Sphinx + autodoc

**Rationale:**
- ✅ Automatic docs from docstrings
- ✅ Type hint support
- ✅ Standard for Python projects
- ✅ Can use Google docstring style
- ✅ Integrates with Read the Docs

### For TypeScript MCP Servers

**Primary:** TypeDoc

**Rationale:**
- ✅ Zero config
- ✅ Perfect TypeScript integration
- ✅ Clean output
- ✅ Fast generation
- ✅ Type information included

### For C/C++ Projects (if any)

**Primary:** Sphinx + Breathe + Doxygen

**Rationale:**
- ✅ Industry standard
- ✅ Detailed API docs
- ✅ Multiple output formats
- ✅ Code-to-docs synchronization

---

## Implementation Plan

### Phase 1: MkDocs for Oaich-mcp-config

```bash
# Install MkDocs Material
uv pip install mkdocs-material

# Create docs directory
mkdir -p docs

# Initialize MkDocs
mkdocs new .

# Edit mkdocs.yml (use config above)
# Write documentation pages

# Serve locally
mkdocs serve

# Build for deployment
mkdocs build
```

### Phase 2: Sphinx for Python MCP Servers

```bash
# Install Sphinx
uv pip install sphinx sphinx-rtd-theme sphinx-autodoc-typehints

# Initialize Sphinx
sphinx-quickstart docs

# Configure autodoc in conf.py
# Write RST files
# Generate API docs with sphinx-apidoc

# Build docs
make html
```

### Phase 3: TypeDoc for TypeScript Servers

```bash
# Install TypeDoc
npm install --save-dev typedoc

# Create typedoc.json
# Add JSDoc comments to code

# Generate docs
npx typedoc
```

---

## Deployment Options

### GitHub Pages (Free)

```bash
# MkDocs
mkdocs gh-deploy

# Sphinx
# Use sphinx-to-github or similar

# TypeDoc
# Copy docs/ to gh-pages branch
```

### Read the Docs (Free, Auto-build)

```yaml
# .readthedocs.yml
version: 2

build:
  os: ubuntu-22.04
  tools:
    python: "3.11"

sphinx:
  configuration: docs/conf.py

python:
  install:
    - requirements: docs/requirements.txt
```

### Self-Hosted (CachyOS Server)

```bash
# Serve with nginx
sudo pacman -S nginx

# Configure nginx to serve docs/build/html
# Or use python -m http.server for testing
```

---

## Conclusion

**For Oaich-mcp-config:** Use MkDocs + Material Theme
- Beautiful, easy to maintain, perfect for user documentation
- Can be enhanced with Sphinx for Python API docs if needed

**For MCP Server Development:**
- Python: Sphinx + autodoc
- TypeScript: TypeDoc
- C/C++: Sphinx + Breathe + Doxygen

All tools are mature, well-maintained, and actively used in production by major projects in 2025.

---

## Resources

### MCP Documentation
- Specification: https://modelcontextprotocol.io/specification/2025-06-18
- Python SDK: https://github.com/modelcontextprotocol/python-sdk
- TypeScript SDK: https://github.com/modelcontextprotocol/typescript-sdk

### Documentation Tools
- MkDocs: https://www.mkdocs.org
- Material Theme: https://squidfunk.github.io/mkdocs-material/
- Sphinx: https://www.sphinx-doc.org
- Doxygen: https://www.doxygen.nl
- Breathe: https://breathe.readthedocs.io
- TypeDoc: https://typedoc.org

---

*Document compiled: 2025-10-30*
*Based on October 2025 research*
*Author: Oaich (eirikr)*
