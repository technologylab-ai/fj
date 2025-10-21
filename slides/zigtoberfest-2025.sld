# #############################################################
# ##   T  E  M  P  L  A  T  E  S
# #############################################################

# -- global setup
@fontsize=16
@font=./assets/fonts/GeorgiaPro-Semibold.ttf
@font_bold=./assets/fonts/GeorgiaPro-Bold.ttf
@font_italic=./assets/fonts/GeorgiaPro-SemiboldItalic.ttf
@font_bold_italic=./assets/fonts/GeorgiaPro-BoldItalic.ttf
@font_extra=../../../renerocksai/rayslides/src/assets/press-start-2p.ttf
@underline_width=2
@color=#000000ff
@bullet_color=#cd0f2dff

# Override bullet symbol default of > with the bullet point
@bullet_symbol=•

# -------------------------------------------------------------
# -- definitions for later
# -------------------------------------------------------------

@let PRESENTATION_TITLE = Running your Company on the Command-Line
@let PRESENTATION_SUBTITLE = With <$yellow$>Zig</>, LaTeX, Git, and ZAP!
@let PRESENTATION_AUTHOR = @renerocksai
@let PRESENTATION_DATE = Zigtoberfest 2025-10-25

@let white = #f0f3f8ff
@let grey =#aab6c5ff
@let lightgrey=#A0A0A0ff
@let darkgrey=#808080b0
@let green = #2de86cff
@let yellow = #ffd447ff
@let blue = #3399FFFF
@let cyan = #00ffe0ff
@let red = #ff5c57ff

@push logo img=assets/logos/techlab-logo-notext.png x=1830 y=25 w=64 h=64
@push slide_title    x=50 y=40 w=1700 h=223 fontsize=45 color=$white$
@push slide_bar      x=50 y=95 w=100  h=5  color=$blue$
@push slide_number x=1803 y=1027 w=40   h=40  fontsize=20 color=#404040ff text=$slide_number

@push bigbox       x=110  y=181  w=1700 h=800 fontsize=56 color=$grey$
@push leftbox      x=110  y=181  w=800  h=800 fontsize=56 color=$grey$
@push rightbox     x=1000 y=181  w=820  h=800 fontsize=56 color=$grey$
@push smallbox     x=110  y=181  w=1700 h=800 fontsize=30 color=$grey$

# -------------------------------------------------------------
# -- intro slide template
# -------------------------------------------------------------
@bg color=#0d1117ff
@pop slide_title    color=$grey$ text=_AI Research & Technology Lab_
@pop logo
@pop slide_bar
@push intro_title    x=50 y=250 w=1900 h=246 fontsize=88 color=$white$
@push intro_subtitle x=60 y=400 w=1400 h=246 fontsize=45 color=$blue$
@push intro_authors  x=60 y=1000 w=836 h=246 fontsize=25 color=$cyan$
@push intro_date  x=1600 y=1000 w=836 h=246 fontsize=25 color=$grey$
@pushslide intro

# -------------------------------------------------------------
# -- content slide template
# -------------------------------------------------------------
@bg color=#0d1117ff
@pop logo
@pop slide_number
@pop slide_bar
@pushslide content

# -------------------------------------------------------------
# -- thankyou slide template
# -------------------------------------------------------------
@bg color=#0d1117ff
@pop slide_title    color=$grey$ text=_AI Research & Technology Lab_
@push thankyou_text x=50 y=650 w=1870 color=$red$ fontsize=128 text=**THANK YOU for your attention!**
@pop logo
@pop slide_bar
@push thankyou_title    x=50 y=200 w=1800 h=246 fontsize=96 color=$white$
@push thankyou_subtitle x=60 y=450 w=1400 h=246 fontsize=45 color=$blue$
@push thankyou_authors  x=60 y=1000 w=836 h=246 fontsize=25 color=$cyan$
@push thankyou_date  x=1600 y=1000 w=836 h=246 fontsize=25 color=$grey$
@pushslide thankyou


# #############################################################
# ##   S  L  I  D  E  S
# #############################################################

# -------------------------------------------------------------
# INTRO SLIDE
# -------------------------------------------------------------
@popslide intro
@pop intro_title text=**$PRESENTATION_TITLE$**
@pop intro_subtitle text=**$PRESENTATION_SUBTITLE$**
@pop intro_date text=**$PRESENTATION_DATE$**
@pop intro_authors text=_$PRESENTATION_AUTHOR$_
@box img=assets/logos/fj.png x=800 y=530 w=384 h=384


# #############################################################
# ## BACKSTORY
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**A Company Needs Invoices**
@pop bigbox
Running a one-person company requires:
_
- <$blue$>**Professional invoices**</> with proper VAT calculations
_
- <$yellow$>**Offers (quotations)**</> that can later become invoices
_
- <$green$>**Client database**</> with addresses, VAT numbers, contact info
_
- <$cyan$>**Incremental ID assignment**</> on a per-year basis
_
- **Letters** for official correspondence


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**What's Hard About Invoices?**
@pop bigbox
Word and Excel are error-prone:
_
- Easy to forget incrementing the invoice number
_
- Manual calculations: **N items × price**, **+ VAT**, **= total**
_
- Copy-paste errors with client data
_
- No version history
_
- No structured workflow: **offer → invoice**


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Original Tool (circa mid 2000's)**
@pop bigbox
- Built with: **bash**, **sed**, **awk**, **pdflatex**
_
- Data stored in CSV files and text templates
_
- Ran in a dedicated VM (for snapshots)
_
- The promise: <$green$>_"Future-proof: Shell scripts work forever!"_</>
_
- Reality check in 2025: <$red$>Could not even run the  ~~_**init**_~~  command</>
_
- **Lesson learned**: Source code is NOT necessarily future-proof


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Decision**
@pop bigbox line_height=1.1
Now I know a bit more than 20 years ago, and ... <$yellow$>**Zig**</>
_
- **The new promise:** <$green$>**Static binaries ARE future-proof**</>
_
-    <$darkgrey$>_(this time it ~~**will**~~ work!)_</>

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Decision**
@pop bigbox line_height=1.1
Now I know a bit more than 20 years ago, and ... <$yellow$>**Zig**</>
_
- **The new promise:** <$green$>**Static binaries ARE future-proof**</>
_
-    <$darkgrey$>_(this time it ~~**will**~~ work!)_</>
_
<$blue$>`X86 is going to outlive us all!`</>

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Decision**
@pop bigbox line_height=1.5
~~**Time to rebuild it properly:**~~
_
- <$yellow$>Write it in Zig!</>
- <$blue$>Maintainable, readable code</>
- <$green$>Statically linked binary</> <$darkgrey$>_(musl if necessary)_</>
- Git-managed document repository
- <$cyan$>LaTeX for professional PDFs</>
- <$red$>**CLI-first design**</>



# #############################################################
# ## BUILDING THE CLI
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The ZLGZZZ Stack**
@pop bigbox line_height=1.2
- <$yellow$>**Zig 0.15.1**</>       _<$darkgrey$>(yes, I know...)</>_
_
- <$cyan$>**LaTeX**</> (pdflatex) for PDF generation
_
- <$blue$>**Git**</> for version control and document history
_
- Dependencies:
    - <$red$>**zli**</>: CLI argument parsing
    - <$green$>**zeit**</>: date/time handling
    - <$darkgrey$>_(later)_ **zap**:</> web server framework


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**CLI Structure - The Commands**
@pop smallbox fontsize=70
<$red$>fj</> <$blue$>init</>         [--generate] <config.json>
_
<$red$>fj</> <$blue$>client</>    [new|show|checkout|commit|list]
<$red$>fj</> <$blue$>rate</>        [new|show|checkout|commit|list]
_
<$red$>fj</> <$blue$>invoice</> [new|compile|commit|show|list|checkout|open]
<$red$>fj</> <$blue$>offer</>      [new|compile|commit|show|list|checkout|open]
<$red$>fj</> <$blue$>letter</>     [new|compile|commit|show|list|checkout|open]
_
<$red$>fj</> <$blue$>git</>           [remote|pull|push|status]


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**CLI Design - Typed Command Structs**
@pop bigbox x=110 y=151 fontsize=38 line_height=1.1
Commands are defined as structs:

@box x=110  y=231  w=1700 h=800 img=./assets/images/InvoiceCommand.png

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Why Typed Structs Matter**
@pop bigbox
These structs provide:
_
- <$green$>**Compile-time validation**</> of command structure
_
- **Self-documenting** code
_
- <$blue$>**Type-safe**</> command handling
_
_
_
<$yellow$>**Key insight**</> — Same structs work in web handlers!


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Document Workflow**
@pop bigbox line_height=1.2
**1. <$blue$>new</>** — Creates working directory with temporary ID:
    - Template LaTeX file
    - JSON metadata (client, date, rates, etc.)
    - CSV for billable items
    - Naming: invoice--YEAR-XXX--client/
_
**2. <$blue$>compile</>** — Runs pdflatex <$darkgrey$>-></> generates PDF
_
**3. <$blue$>commit</>** — Assigns permanent ID, moves to git repo, commits


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Document Workflow (visual)**
@box x=0  y=181  w=1920 h=800 img=./assets/images/document_workflow.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The FJ_HOME Structure**
# Placeholder for diagram
@box img=./assets/images/fj_home_structure_vert.png x=150 y=200 w=1620 h=800
@box x=0  y=0  w=1920 h=1080 img=./assets/images/fj_home_structure_vert.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Learning 1: Memory Management for CLI**
@pop bigbox
CLI programs are short-lived, one-shot:
_
- <$green$>**Use arena allocator**</>
_
- Free everything at the end
_
- Simple and efficient
_
- No need for complex lifetime management


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Learning 2: Error Handling with fatal()**
@pop bigbox
CLI tools can exit immediately on error:
_
- <$white$>**std.process.fatal()**</> — returns <$yellow$>**noreturn**</>
_
- No need to bubble errors up call stack
_
_
Clean and simple:
_
                    <$cyan$>const expanded = expandHomeDir(arena, path);</>
_
                    <$lightgrey$>// No try, no error union</>
                    <$lightgrey$>// Just works or exits</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Learning 3: Printing Version**
@pop bigbox
_
Version should come from <$lightgrey$>build.zig.zon</>
_
_
Problem: Can't <$cyan$>@import</> it    _<$darkgrey$>(outside of src/,  variable deps)</>_
_
_
Solution: <$cyan$>@embedFile</> in <$red$>build.zig</>, but parse  **<$white$>at runtime</>**
_
_
_
_
             _<$blue$>apparently, variable deps issue is solved in zig > 0.14.0</>_

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Learning 3: Printing Version**
@pop leftbox x=110 y=220 w=832 h=732 img=./assets/images/print_version_1.png
@pop rightbox  img=./assets/images/print_version_2.png

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Learning 4: Atomic ID Assignment**
@pop bigbox
Multiple users might commit documents simultaneously
_
Solution: <$green$>**File locking**</> on <$blue$>.id</> files
_
- Each document type has <$blue$>.id</> file
_
- Lock, read, increment, write, unlock
_
- Ensures no ID collisions
_
- <$yellow$>Critical for multi-user scenarios</> (web server!)


# #############################################################
# ## DEMO 1 MARKER
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Demo Time: The CLI**
@pop bigbox
_
_
<$cyan$>**LIVE DEMO**</>
_
_
From <$yellow$>zero</> to invoice with the CLI


# #############################################################
# ## WEB INTERFACE - CHALLENGES
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Web Idea**
@pop bigbox
CLI is great, but...
_
- Wouldn't a <$blue$>**dashboard**</> be nice?
_
- A tool for travel expenses would be nice, with <$green$>**image handling**</> (receipts)
_
- Access from <$cyan$>**anywhere**</> <$lightgrey$>(safe)</>?
_
- **Decision:** Add <$yellow$>**fj serve**</> command


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Enter ZAP**
@pop bigbox
<$yellow$>**ZAP**</> — Fast HTTP server framework for Zig
_
- Built on **facil.io** (C library)
_
- Used in production
_
- Great for adding web UIs and HTTP APIs to existing tools  <$lightgrey$>(IMHO)</>
_
- Opinionated
_
- <$red$>You should not use ZAP</>  <$lightgrey$>_(with expectations)_</>
        - it's threaded, not async
        - wait for zig's  <$cyan$>**std.Io.***</>
        - also check out <$blue$>http.zig</>, <$green$>Jetzig</>, ...

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Architecture Challenge**
@pop bigbox
_
<$blue$>**CLI**</>: short-lived, single-threaded, can exit on error
_
vs.
_
<$green$>**Web**</>: long-lived, multi-threaded, must stay running
_
_
<$red$>How to reuse the code?</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Challenge 1: The fatal() Problem**
@pop bigbox line_height=1.5
CLI <$cyan$>fatal()</> calls <$cyan$>std.process.fatal()</> <$lightgrey$>-></> <$red$>exits process</>
_
Web server can't exit on user error!
_
Need mode-aware <$cyan$>fatal()</>:
- <$blue$>CLI mode</> — log and exit
- <$green$>Server mode</> — capture message, return error


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Solution: Dual-Mode fatal()**
@pop bigbox img=./assets/images/fatal.zig.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Magic of !noreturn**
@pop bigbox
Return type: <$yellow$>**error union of noreturn**</>
_
- CLI mode: never returns (exits) <$lightgrey$> -></> <$red$>noreturn</>
_
- Server mode: returns  <$red$>error</>
_
- <$green$>Same function signature works in both contexts!</>
_
- Assignment still works with  <$yellow$>try</>:
_
                <$cyan$>const x = try fatal(</><$lightgrey$>...</><$cyan$>);</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Challenge 2: Current Working Directory**
@pop bigbox
CLI happily changes cwd with <$cyan$>std.os.chdir()</>
_
Web server is <$red$>**multi-threaded**</>
_
Changing cwd affects <$yellow$>**ALL threads!**</>
_
Solution: <$green$>**Absolute paths everywhere**</> in server mode


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Challenge 3: Reusing CLI Structures**
@pop leftbox fontsize=56
_
Remember those typed command structs?
_
They're <$green$>**decoupled from command-line parsing**</>!
_
In web endpoint, pass to same business logic as CLI!

@pop rightbox img=./assets/images/server_reusing_cli.png


# #############################################################
# ## ZAP ARCHITECTURE
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**ZAP App Setup: Type-Safe Context**
@pop bigbox fontsize=48
<$darkgrey$>// server.zig</>
const App = zap.App.Create(Context);
try App.init(allocator, &context, .{});
<$darkgrey$>// ...</>
_
try App.listen(.{
    .interface = "127.0.0.1",
    .port = 3000,
});
_
zap.start(.{
    .threads = 2,
    .workers = 1,
});
_
<$lightgrey$>App is</> <$yellow$>**parameterized by Context type**</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Context: Shared State**
@pop leftbox fontsize=48
_
- Allocator
- Username, password lookup table for authentication
- Authenticator state
- Application config
- Embedded assets
- <$cyan$>unhandledRequest()</> handler
        - if no dedicated endpoint handles the request
        - we abuse it to send favico
        - else we redirect to
            <$lightgrey$>/init</> or <$lightgrey$>/dashboard</>
_
<$green$>**All endpoints get same context structure**</>

@pop rightbox img=./assets/images/context.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Endpoint Structure: Consistent Pattern**
@pop bigbox img=./assets/images/logout_endpoint.zig.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Generic Endpoint Factories**
@pop bigbox
<$yellow$>**Compile-time polymorphism**</> for DRY code:
_

@pop bigbox x=350 y=300 w=1200 h=600 img=./assets/images/endpointfactories.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Authentication: "Layering" Middleware**
@pop bigbox img=./assets/images/auth_inject.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**PreRouter: Initialization Guard**
@pop bigbox
The <$yellow$>**"secret sauce"**</> — ensuring fj is initialized:
_

@pop bigbox x=110 y=250 w=1700 h=800 img=./assets/images/prerouter.zig.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Middleware Layering**
@pop bigbox
The registration chain:
_

@pop bigbox x=110 y=250 w=1700 h=800 img=./assets/images/regchain.zig.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Middleware Layering (visual)**
@pop bigbox x=110 y=120 w=1700 h=950 img=./assets/images/middleware_layering.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Request Flow Through Layers**
@pop bigbox x=0 y=120 w=1920 h=950 img=./assets/images/request_flow.png


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Sub-Routing Pattern**
@pop bigbox
Manual path matching in endpoints:

@pop bigbox x=110 y=250 w=1700 h=700 img=./assets/images/subrouting.zig.png

@pop bigbox x=110 y=980 w=1700 h=700
<$green$>**Simple, explicit, no framework magic**</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Template Rendering Pipeline**
@pop bigbox img=./assets/images/mustache.zig.png

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Asset Embedding**
@pop bigbox
- <$red$>**ALL**</> static assets for the web server are embedded
_
- <$red$>**ALL**</> mustache templates for the web server are embedded
_
- <$red$>**ALL**</> LaTeX, template, ... files for the CLI are embedded
_
_
<$yellow$>**Zero file I/O • All bundled in binary**</>
_

<$cyan$>**Single executable file deployment**</>

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Key ZAP App Architecture Patterns**
@pop bigbox line_height=1.5
Summary of what makes this structure elegant:         <$darkgrey$>_(IMHO)_</>
_
**1.** <$yellow$>Compile-time middleware composition</> (no runtime overhead)
**2.** <$green$>Generic endpoint factories</> (code reuse via comptime)
**3.** <$blue$>Type-safe context injection</> (shared state management)
**4.** <$cyan$>Decorator pattern layers</> (PreRouter + Authenticating)
**5.** <$white$>Explicit sub-routing</> (clear control flow)
**6.** <$red$>Request-scoped arena allocators</> (clean memory management)


# #############################################################
# ## WEB FEATURES & C INTEGRATION
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Web Features Beyond CLI features**
@pop bigbox line_height=1.2
- <$blue$>**Dashboard**</> with document overview
_
- <$green$>**Travel expense management**</>:
    - Dynamic travel details, locations, transports, ... form
    - Upload receipt images
    - Generate combined PDF with cover page
    - ZIP download of all receipts
_
- <$cyan$>Live git status</> display
_
- <$yellow$>File browsers</> for documents


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Image Processing Challenge**
@pop bigbox
Travel expenses needed:
_
- C dependencies: **stb__image**, **stb___image__resize**, **miniz**, **pdfgen**
_
- Resize images to A4 proportions
_
- Convert images to PDF
_
- Generate cover page with metadata (with pdfgen, not LaTeX)
_
- ZIP all PDFs
_
- All integrated via <$green$>**Zig's C interop**</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Build System Integration**
@pop bigbox x=110 y=150 w=1700 h=700 img=./assets/images/build.zig.png

@pop bigbox x=110 y=910 w=1700 h=700
<$green$>**Seamless C integration • No separate build steps**</>


# #############################################################
# ## DEMO 2 MARKER
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Demo Time: The Web Interface**
@pop bigbox
_
_
<$cyan$>**LIVE DEMO**</>
_
_
Web dashboard and features


# #############################################################
# ## LESSONS LEARNED
# #############################################################

# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Key Learnings: CLI Development**
@pop bigbox
- Use <$green$>**arena allocator**</> for one-shot programs
_
- <$yellow$>**fatal() with noreturn**</> for clean error handling
_
- <$blue$>**Embed build.zig.zon**</> for version reporting
_
- <$cyan$>**Typed command structs**</> are valuable abstractions
_
- <$white$>**File locking**</> for atomic operations


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Key Learnings: Web Enablement**
@pop bigbox
- <$yellow$>**Dual-mode error handling**</> with !noreturn
_
- <$red$>Avoid changing cwd</> in multi-threaded apps
_
- <$green$>**Reuse CLI logic**</> by separating parsing from business logic
_
- <$blue$>**ZAP**</> makes web servers in Zig approachable
_
- <$cyan$>**C interop**</> is powerful and practical


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Key Learnings: ZAP Architecture**
@pop bigbox
- <$yellow$>**Compile-time middleware composition**</> (zero runtime overhead)
_
- <$green$>**Generic endpoint factories**</> (comptime polymorphism)
_
- <$blue$>**Type-safe context injection**</> (shared state management)
_
- <$cyan$>**Decorator pattern**</> for layered middleware
_
- <$white$>**Request-scoped allocators**</> (clean memory management)
_
- **Explicit sub-routing** (no framework magic)


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Patterns That Transferred CLI -> Web**
@pop leftbox
**Transferred well:**
_
- Typed command structs
_
- Business logic functions
_
- JSON data structures
_
- Git operations
_
- LaTeX compilation

@pop rightbox
**Needed adaptation:**
_
- Error handling
    (fatal -> dual-mode)
_
- Path handling
    (cwd -> absolute paths)
_
- Memory management
    (arena -> request-scoped)


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**The Journey**
@pop leftbox
**From:**
_
- Brittle shell scripts
- No version control
- CLI only
- "Future-proof" scripts

@pop rightbox
**To:**
_
- Maintainable Zig code
- Git-managed repository
- CLI + Web interface
- Automated & validated
- <$green$>Actually future-proof binary</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Why Build Your Own?**
@pop bigbox
- <$blue$>**Perfect fit**</> for YOUR workflow
_
- <$green$>No subscription fees</> or vendor lock-in
_
- <$yellow$>Complete control</> over data and features
_
- <$cyan$>Learning opportunity</>
_
- <$white$>**It's actually fun!**</>


# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Bonus: Encrypted S3 Backup**
@pop bigbox
Optional, handled outside of the app:
_
- **git-remote-gcrypt** for encrypted remotes
_
- <$green$>Client-side GPG encryption</>
_
- **S3** as backup destination
_
- <$yellow$>Your data, your keys, your control</>
_
_
_
_
<$blue$>See doc/push-to-s3.md in repository for details</>

# -------------------------------------------------------------
@popslide thankyou
@pop thankyou_title text=**$PRESENTATION_TITLE$**
@pop thankyou_subtitle text=**$PRESENTATION_SUBTITLE$**
@pop thankyou_authors text=_$PRESENTATION_AUTHOR$_
@pop thankyou_text
@pop thankyou_date text=**$PRESENTATION_DATE$**
@box img=assets/logos/fj.png x=1550 y=150 w=320 h=320

# -------------------------------------------------------------
# eof
