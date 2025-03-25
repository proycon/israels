from subprocess import run
from tf.core.helpers import console
from tf.core.files import (
    dirContents,
    dirExists,
    dirRemove,
    dirCopy,
    initTree,
    fileExists,
    extNm,
    fileRemove,
    expanduser,
)


ORG = "HuygensING"
REPO = "israels"
BACKEND = "github"
LOGO = "logo"

PAGES = "pages"
_REPODIR = expanduser(f"~/{BACKEND}/{ORG}/{REPO}")
_DATADIR = f"{_REPODIR}/_local"
_REPORTDIR = f"{_REPODIR}/report"
SCANDIR = f"{_REPODIR}/scans"
THUMBDIR = f"{_REPODIR}/thumb"
THUMBPAGEDIR = f"{THUMBDIR}/{PAGES}"
LOGODIR = f"{THUMBDIR}/{LOGO}"

REPORT_SCANDIR = f"{_REPORTDIR}/scanreports"
REPORT_SCANERRORS = f"{REPORT_SCANDIR}/scanerrors.txt"


SCAN_QUALITY = "15%"
SCAN_RESIZE = "35%"
SCAN_COMMAND = "/opt/homebrew/bin/magick"

SCAN_OPTIONS = ["-quality", SCAN_QUALITY, "-resize", SCAN_RESIZE]
SCAN_EXT = ("jpf", "jpg")

SIZES_COMMAND = "/opt/homebrew/bin/identify"
SIZES_OPTIONS = ["-ping", "-format", "%w %h"]

DS_STORE = ".DS_Store"


class Scans:
    def __init__(self, subset=False, silent=False, force=False):
        scanDir = "scans-subset" if subset else "scans"
        srcImageDir = f"{_DATADIR}/{scanDir}"
        pageInDir = f"{srcImageDir}/{PAGES}"
        logoInDir = f"{srcImageDir}/{LOGO}"

        self.srcImageDir = srcImageDir
        self.pageInDir = pageInDir
        self.logoInDir = logoInDir

        initTree(_REPORTDIR, fresh=False)
        initTree(REPORT_SCANDIR, fresh=False)

        self.silent = silent
        self.force = force
        self.errors = {}
        self.error = False

    def ingest(self, dry=False):
        if self.error:
            return

        silent = self.silent
        force = self.force

        self.ingestLogo(dry=dry)

        dstDir = f"{SCANDIR}/{PAGES}"

        if dirExists(dstDir) and not force and not dry:
            if not silent:
                console(
                    f"\tAlready ingested {PAGES}. "
                    f"Remove {dstDir} or pass --force to ingest again"
                )
        else:
            self.ingestPages(dry=dry)

    def ingestPages(self, dry=False):
        if self.error:
            return

        pageInDir = self.pageInDir
        silent = self.silent
        scanExt = SCAN_EXT[0]
        pageFiles = dirContents(pageInDir)[0]

        if not silent:
            console(f"{len(pageFiles):>4} files")

        n = 0

        for file in pageFiles:
            if extNm(file) != scanExt:
                continue

            n += 1

        if not silent:
            console(f"{n:>4} {SCAN_EXT[0]} files")

    def ingestLogo(self, dry=False):
        if self.error:
            return

        logoInDir = self.logoInDir

        if not dry:
            dirRemove(LOGODIR)
            dirCopy(logoInDir, LOGODIR)

    def process(self, force=False):
        if self.error:
            return

        if force is None:
            force = self.force

        silent = self.silent
        srcImageDir = self.srcImageDir

        plabel = "originals"
        dlabel = "thumbnails"

        srcDir = f"{srcImageDir}/{PAGES}"
        destDir = f"{THUMBDIR}/{PAGES}"
        sizesFile = f"{THUMBDIR}/sizes_{PAGES}.tsv"

        if force or not dirExists(destDir):
            self.doThumb(srcDir, destDir, *SCAN_EXT, plabel, dlabel)
        else:
            if not silent:
                console(f"Already present: {dlabel} ({PAGES})")

        if force or not fileExists(sizesFile):
            self.doSizes(destDir, SCAN_EXT[1], sizesFile, dlabel)
        else:
            if not silent:
                console(f"Already present: sizes file {dlabel} ({PAGES})")

    def doSizes(self, imDir, ext, sizesFile, label):
        if self.error:
            return

        silent = self.silent
        fileRemove(sizesFile)

        fileNames = dirContents(imDir)[0]
        items = []

        for fileName in sorted(fileNames):
            if fileName == DS_STORE:
                continue

            thisExt = extNm(fileName)

            if thisExt != ext:
                continue

            base = fileName.removesuffix(f".{thisExt}")
            items.append((base, f"{imDir}/{fileName}"))

        console(f"\tGet sizes of {len(items)} {label} ({PAGES})")
        j = 0
        nItems = len(items)

        sizes = []

        for i, (base, fromFile) in enumerate(sorted(items)):
            if j == 100:
                perc = int(round(i * 100 / nItems))

                if not silent:
                    console(f"\t\t{perc:>3}% done")

                j = 0

            status = run(
                [SIZES_COMMAND] + SIZES_OPTIONS + [fromFile], capture_output=True
            )
            j += 1

            if status.returncode != 0:
                console(status.stderr.decode("utf-8"), error=True)
            else:
                (w, h) = status.stdout.decode("utf-8").strip().split()
                sizes.append((base, w, h))

        perc = 100

        if not silent:
            console(f"\t\t{perc:>3}% done")

        with open(sizesFile, "w") as fh:
            fh.write("file\twidth\theight\n")

            for file, w, h in sizes:
                fh.write(f"{file}\t{w}\t{h}\n")

    def doThumb(self, fromDir, toDir, extIn, extOut, plabel, dlabel):
        if self.error:
            return

        silent = self.silent
        initTree(toDir, fresh=True)

        fileNames = dirContents(fromDir)[0]
        items = []

        for fileName in sorted(fileNames):
            if fileName == DS_STORE:
                continue

            thisExt = extNm(fileName)
            base = fileName.removesuffix(f".{thisExt}")

            if thisExt != extIn:
                continue

            items.append((base, f"{fromDir}/{fileName}", f"{toDir}/{base}.{extOut}"))

        console(f"\tConvert {len(items)} {plabel} to {dlabel} ({PAGES})")

        j = 0
        nItems = len(items)

        for i, (base, fromFile, toFile) in enumerate(sorted(items)):
            if j == 100:
                perc = int(round(i * 100 / nItems))

                if not silent:
                    console(f"\t\t{perc:>3}% done")

                j = 0

            run([SCAN_COMMAND] + [fromFile] + SCAN_OPTIONS + [toFile])
            j += 1

        perc = 100
        if not silent:
            console(f"\t\t{perc:>3}% done")
