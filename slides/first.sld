# #############################################################
# ##   T  E  M  P  L  A  T  E  S
# #############################################################

# -- global setup
@fontsize=36
@font=./assets/fonts/GeorgiaPro-Semibold.ttf
# @font=./assets/fonts/GeorgiaPro-Light.ttf
@font_bold=./assets/fonts/GeorgiaPro-Bold.ttf
@font_italic=./assets/fonts/GeorgiaPro-SemiboldItalic.ttf
# @font_italic=./assets/fonts/GeorgiaPro-Italic.ttf
@font_bold_italic=./assets/fonts/GeorgiaPro-BoldItalic.ttf
@underline_width=2
@color=#000000ff
@bullet_color=#cd0f2dff


# Override bullet symbol default of > with the bullet point
@bullet_symbol=•

# -------------------------------------------------------------
# -- definitions for later
# -------------------------------------------------------------

@let PRESENTATION_TITLE = The Great AI Future
@let PRESENTATION_SUBTITLE = An Introduction
@let PRESENTATION_AUTHOR = Rene Schallner
@let PRESENTATION_DATE = 2025-08-01

@let white = #f0f3f8ff
@let grey =#aab6c5ff
@let green = #2de86cff
@let yellow = #ffd447ff
@let blue = #3399FFFF
@let cyan = #00ffe0ff
@let red = #ff5c57ff



@push logo img=assets/logos/techlab-logo-notext.png x=1830 y=25 w=64 h=64
@push slide_title    x=50 y=40 w=1700 h=223 fontsize=45 color=$white$
@push slide_bar      x=50 y=95 w=100  h=5  color=$blue$

@push slide_number x=1803 y=1027 w=40   h=40  fontsize=20 color=#404040ff text=$slide_number

@push sources_info x=110  y=960  w=1758 h=129 fontsize=20 color=#bfbfbfff text=Sources:

@push bigbox       x=110  y=181  w=1700 h=971 fontsize=45 color=$grey$
@push leftbox      x=110  y=181  w=850  h=861 fontsize=45 color=$grey$
@push rightbox     x=1080 y=181  w=850  h=879 fontsize=45 color=$grey$


# -------------------------------------------------------------
# -- intro slide template
# -------------------------------------------------------------
@bg color=#0d1117ff
@pop slide_title    color=$grey$ text=_AI Research & Technology Lab_
@pop logo
@pop slide_bar
@push intro_title    x=50 y=300 w=1800 h=246 fontsize=96 color=$white$
@push intro_subtitle x=60 y=450 w=1400 h=246 fontsize=45 color=$blue$
@push intro_authors  x=60 y=1000 w=836 h=246 fontsize=25 color=$cyan$
@push intro_date  x=1750 y=1000 w=836 h=246 fontsize=25 color=$grey$
# the following pushslide will the slide cause to be pushed, not rendered
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
# -- chapter slide template
# -------------------------------------------------------------
# Note: with each new @slide, the current item context will be cleared.
#       That means, you will not inherit attributes from previous slides.

@bg color=#0d1117ff
@pop logo
@push chapter_number   x=50 y=280 w=260 h=362 fontsize=400 color=$grey$
@push chapter_title    x=520 y=330 w=1200 h=114 fontsize=128  color=$white$
@push chapter_subtitle x=530 y=500 w=1200 h=141 fontsize=45 color=$blue$
@pushslide chapter


### # -------------------------------------------------------------
### # -- thankyou slide template
### # -------------------------------------------------------------
@bg color=#0d1117ff
@pop slide_title    color=$grey$ text=_AI Research & Technology Lab_
@push thankyou_text    x=240 y=520 w=1870 color=$red$ fontsize=200 text=**THANK YOU for your attention!**
# @push thankyou_text    x=250 y=600 color=$red$ fontsize=100 text=**THANK YOU for your attention!**
@pop logo
@pop slide_bar
@push thankyou_title    x=50 y=300 w=1800 h=246 fontsize=96 color=$white$
@push thankyou_subtitle x=60 y=450 w=1400 h=246 fontsize=45 color=$blue$
@push thankyou_authors  x=60 y=1000 w=836 h=246 fontsize=25 color=$cyan$
@push thankyou_date  x=1750 y=1000 w=836 h=246 fontsize=25 color=$grey$
@pushslide thankyou


# #############################################################
# ##   S  L  I  D  E  S
# #############################################################

# -------------------------------------------------------------
@popslide intro
@pop intro_title text=**$PRESENTATION_TITLE$**
@pop intro_subtitle text=**$PRESENTATION_SUBTITLE$**
@pop intro_date text=**$PRESENTATION_DATE$**
@pop intro_authors text=_$PRESENTATION_AUTHOR$_

@popslide chapter
@pop chapter_number text=1
@pop chapter_title text=**Hello new AI World**
@pop chapter_subtitle text=The new AI World is going to be great



# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Overview**
@pop bigbox bullet_symbol=•
- **Presentations are created in a simple, markdown-based text format**
        - <$blue$>_makes your slides totally GitHub-friendly_</>
_
- **One single (mostly static) executable** _ — no install required._
        - <$green$>_for Windows, Linux (and Mac, if you build it yourself)_</>
_
_
- **Built-in editor:** _create, edit, present, ..., make changes while presenting_
        - <$yellow$>_press [E] key to try it out_</>
_
- **Support for clickers**
        - <$red$>_Connect your clicker and try it out_</>
_
- **Virtual laser pointer in different sizes**
        - <$cyan$>_press [L] key and [SHIFT] + [L] to try it out_</>



# -------------------------------------------------------------
@popslide content
@pop slide_title text=**Formatting Text**

@pop  sources_info
here come the sources

@pop leftbox
This is Markdown _**ta-dah**_, **tah**, _dah_!
_
empty lines are marked with just an _ underscore
_
- here comes the text
    - even more
        - and let's wrap one more time into a nicely aligned textbox
_
- and so on
_
- now let us create a text that is very likely to need to be wrapped since it is too long to be rendered on a single line of text in the left box
_
- **and so on**, _and on_

@pop rightbox bullet_symbol=*
_
_
_
- here is text in the right box
_
- we changed the **~~bullet symbol~~**!
_
- and so on
_
- here comes more text
_
- and so on
_
- here comes more text
_
- and ~~**so on**~~



# -------------------------------------------------------------
@popslide thankyou
@pop thankyou_title text=**$PRESENTATION_TITLE$**
@pop thankyou_subtitle text=**$PRESENTATION_SUBTITLE$**
@pop thankyou_authors text=_$PRESENTATION_AUTHOR$_
@pop thankyou_text

# -------------------------------------------------------------
# eof commits the slide

