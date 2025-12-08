# WhichSpace

Have you ever forgotten _which space_ is currently active on macOS and wanted a quick way to tell? Didn't think so... but I did!

<img src="Screenshots/WhichSpace.png">

## Features

### Spaces

Display the current Space only, or choose to display all Spaces:

<img src="Screenshots/ShowAllSpaces.png">

> [!NOTE]
> Inactive spaces are dimmed by default.

### Colours

Choose foreground and background colours for each space, or apply one colour to all Spaces:

<img src="Screenshots/ColoursMenu.png" width="60%">

### Icons

Choose from a variety of icons for each space, or apply one icon to all Spaces:

<img src="Screenshots/NumberMenu.png" width="60%">

### Symbols

Use custom symbols instead of numbers for a more personalised look:

<img src="Screenshots/SymbolsMenu.png" width="60%">

### Size

Adjust the scale of the icons in the menu bar:

<img src="Screenshots/SizeMenu.png" width="60%">

## Installation

### Homebrew (recommended)

```text
brew install --cask whichspace
```

#### GitHub

* Download and extract the [latest release](https://github.com/gechr/WhichSpace/releases/latest)
* Run `WhichSpace.app`

> [!WARNING]
> Since the app is not notarized, macOS will show a warning: _"WhichSpace.app" cannot be opened because Apple cannot check it for malicious software._
>
> To bypass this, run the following command in Terminal:
> ```
> xattr -cr /path/to/WhichSpace.app
> ```
> Or right-click the app and select "Open" to add an exception.

## Contributing

[Pull requests](https://github.com/gechr/WhichSpace/pulls) are welcome!
