<p align="center">
    <img width="128" height="128" src="Polc/Assets.xcassets/polc.imageset/polc_256.png" style="filter: drop-shadow(0px 2px 4px rgba(80, 50, 6, 0.2));">
    <h1 align="center"><code style="text-shadow: 0px 3px 10px rgba(8, 0, 6, 0.35); font-size: 3rem; font-family: ui-monospace, Menlo, monospace; font-weight: 800; background: transparent; color: #4d3e56; padding: 0.2rem 0.2rem; border-radius: 6px">Polc</code></h1>
    <h4 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace;">Image, video, PDF and clipboard optimiser</h4>
    <h6 align="center" style="padding: 0; margin: 0; font-family: ui-monospace, monospace; font-weight: 400;">Copy large, paste small, send fast</h6>
</p>

Polc is a personal build of [Clop](https://github.com/FuzzyIdeas/Clop) by The low-tech guys, renamed, with the licence checks, updater, crash reporting and peer-to-peer sharing removed. It is for personal use: it links a copy of the Lowtech library that is not licensed for redistribution.

## Building

You need Xcode 26 or later and [Git LFS](https://git-lfs.com). `Polc/bin.tar.lrz` holds the optimisation tools and is stored in LFS. If it is still an LFS pointer, the build still succeeds, but the app shows an unarchiving error and quits at launch, unless an earlier build already extracted the same tools.

```sh
git lfs pull
Scripts/make-lowtech-local.sh
make build
```

`Scripts/make-lowtech-local.sh` creates `../Lowtech-local` next to this repo: the `Sources/Lowtech` folder of [Lowtech](https://github.com/FuzzyIdeas/Lowtech) at commit `89812896`, with its own `Package.swift`. Don't commit or publish that folder.

`make install` copies the app to `/Applications`. It refuses to run while the Clop build that Polc replaces is still in `/Applications`, so quit Clop and move it to the Bin first.

## Optimise images as soon as you copy them

As long as the Polc app is running, every time you copy an image to your **clipboard**, Polc will **optimise** it to the **smallest possible size**.

The optimised image will have minimal to zero loss in quality, and will be **ready to paste** in any app.

## Screen recordings as small as screenshots

Sending screen recordings becomes 10x faster with Polc. The app will optimise the video as soon as you stop recording.

The video will be available as a **floating thumbnail**, ready for you to **drag and drop** in any app.

Polc can use Apple Silicon's dedicated **Media Engine chip** for battery-efficient video encoding without using the CPU.

## Downscale in a pinch

Get images and videos ready for sharing by scaling them down to any resolution.

Use handy hotkeys or the floating buttons to downscale the image or video and get an even smaller file size.

* <kbd>-</kbd> downscales incrementally from 90% until 10% of the original resolution
* <kbd>1</kbd>..<kbd>9</kbd> are for downscaling to specific sizes

## Power user features

### 1. On-demand optimisation

Press `Ctrl`-`Shift`-`C` to manually optimise the current clipboard.

The action works on *images*, *video* files, *paths*, *URLs*, even base64 encoded images.

For more aggressive optimisation, `Ctrl`-`Shift`-`A` is also available.


### 2. Compatible formats

Polc automatically **converts** less compatible formats like `HEIC`, `tiff`, `mov` to formats understood by most devices.

The conversion is fully configurable from the app settings.

Original files are kept in a backup folder which can be accessed from the app menu.


### 3. macOS Shortcuts

Integrate Polc optimisation in your workflows through **native macOS Shortcuts**.

- Downscale and optimise images that you email weekly
- Download optimised images directly into your slideshow
- ..and so on


## Technical details

Polc uses the following open source tools for optimising files, images and videos:

* `pngquant` for PNG
* `jpegoptim` for JPEG
* `gifsicle` for GIF
* `ffmpeg` for videos
* `libvips` for resizing images
* `gifski` for converting videos to GIFs
* `ghostscript` for optimising PDFs

It may also use `libvips` for resizing images if it is installed on your system.

The app is licensed under [GPLv3](LICENSE).

## Moving from Clop

The first time Polc starts while Clop is not running, it copies Clop's settings, moves `~/Library/Caches/Clop` (where backups live) and `~/Library/Application Support/Clop` to their Polc names, and renames `.clopignore` files in watched folders. Files Clop already optimised are still recognised. On later launches it moves agents' `clop` MCP entries to `polc`, points the `clop` command at Polc, and keeps `clop://` links and the `CLOP_INPUT_FILE` and `CLOP_BIN` script variables working.

macOS ties these to the app's identity, so set them again in Polc:

* Launch at login
* Photos and folder access permissions
* Shortcuts that used Clop actions
* Agent permission rules that name `mcp__clop__…` tools; the tools are now `polc_…`

## Why Polc?

*Polc* is *Clop* spelled backwards. *Clop* is the Romanian word for a traditional straw hat; [the original README](https://github.com/FuzzyIdeas/Clop) tells that story.
