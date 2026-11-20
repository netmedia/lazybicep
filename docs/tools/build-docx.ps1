#Requires -Version 5.1
<#
.SYNOPSIS
Makes docs/LazyBicep-Developer-Guide.docx from docs/DEVELOPER-GUIDE.md in Netmedia's document template.

.DESCRIPTION
pandoc converts the guide with Netmedia's "Document template.docx" as its reference: the template's styles
(Montserrat, the red headings), page, headers and footers (the logo). The guide's first heading is the
document's title, its first paragraph the abstract on the cover; the rest move up a level (## -> Heading 1).

Then Word finishes it as the template's documents look: the logo on the cover, every chapter on a new page,
the tables in the template's Table Grid (10 pt, bold header row), code in Consolas on grey, the screenshots'
captions, the table of contents filled in, the fonts embedded (it looks the same without Montserrat
installed). Word's process is stopped if it hangs.

Run it after changing the guide or its screenshots (docs/tools/screenshots.ps1). Needs pandoc and Word.

.PARAMETER Template
Netmedia's templates folder (Document template.docx, images/logo.png).

.PARAMETER Pdf
Also writes a PDF there.

.EXAMPLE
.\docs\tools\build-docx.ps1
#>
[CmdletBinding()]
param(
    [string]$Template = 'D:\Development\Netmedia\AIToolbelt\plugins\netmedia-document\theme',
    [string]$Pdf
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$docs = Join-Path $repo 'docs'
$docx = Join-Path $docs 'LazyBicep-Developer-Guide.docx'
$reference = Join-Path $Template 'Document template.docx'
$logo = Join-Path $Template 'images\logo.png'
foreach ($f in @($reference, $logo)) { if (-not (Test-Path $f)) { throw "No $f (-Template: Netmedia's templates folder)." } }
if (-not (Get-Command pandoc -ErrorAction SilentlyContinue)) { throw 'pandoc is needed (winget install JohnMacFarlane.Pandoc).' }

# The guide: its title (the first heading) and abstract (the first paragraph) go on the cover.
$lines = @(Get-Content (Join-Path $docs 'DEVELOPER-GUIDE.md') -Encoding UTF8)
$title = $lines[0] -replace '^#\s+', ''
$titleParts = $title -split '\s+[—-]\s+', 2
$at = 1
while ($at -lt $lines.Count -and -not $lines[$at].Trim()) { $at++ }
$abstract = $lines[$at]
$body = Join-Path ([IO.Path]::GetTempPath()) 'lazybicep-guide-body.md'
[IO.File]::WriteAllText($body, (($lines | Select-Object -Skip ($at + 1)) -join "`n"), (New-Object Text.UTF8Encoding $false))
$kit = Get-Content (Join-Path $repo 'infra\kit.json') -Raw -Encoding UTF8 | ConvertFrom-Json

# The template has no styles for what pandoc marks besides headings and code blocks: inline code, the
# screenshots and their captions, the cover's abstract. A copy of it gets them (in the theme's look), so
# pandoc uses them; the template itself is left as it is.
$styles = @'
<w:style w:type="character" w:customStyle="1" w:styleId="VerbatimChar"><w:name w:val="Verbatim Char"/><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas" w:cs="Consolas"/><w:color w:val="333333"/><w:sz w:val="18"/><w:szCs w:val="18"/><w:shd w:val="clear" w:color="auto" w:fill="F2F2F2"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="Figure"><w:name w:val="Figure"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="120"/><w:jc w:val="center"/></w:pPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="CaptionedFigure"><w:name w:val="Captioned Figure"/><w:basedOn w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="120"/><w:jc w:val="center"/></w:pPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="ImageCaption"><w:name w:val="Image Caption"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:after="240"/><w:jc w:val="center"/></w:pPr><w:rPr><w:i/><w:color w:val="666666"/><w:sz w:val="18"/><w:szCs w:val="18"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="Abstract"><w:name w:val="Abstract"/><w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="240" w:after="240"/></w:pPr><w:rPr><w:color w:val="595959"/></w:rPr></w:style>
<w:style w:type="paragraph" w:customStyle="1" w:styleId="AbstractTitle"><w:name w:val="Abstract Title"/><w:basedOn w:val="Normal"/><w:rPr><w:vanish/></w:rPr></w:style>
'@
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$ref = Join-Path ([IO.Path]::GetTempPath()) 'lazybicep-reference.docx'
Copy-Item $reference $ref -Force
$zip = [IO.Compression.ZipFile]::Open($ref, 'Update')
try {
    $entry = $zip.GetEntry('word/styles.xml')
    $reader = New-Object IO.StreamReader($entry.Open())
    $xml = $reader.ReadToEnd()
    $reader.Close()
    $xml = $xml.Replace('</w:styles>', $styles.Replace("`r", '').Replace("`n", '') + '</w:styles>')
    $entry.Delete()
    $writer = New-Object IO.StreamWriter($zip.CreateEntry('word/styles.xml').Open(), (New-Object Text.UTF8Encoding $false))
    $writer.Write($xml)
    $writer.Close()
} finally { $zip.Dispose() }
# The cover's text as metadata (YAML: the abstract is Markdown, its code shows as code).
$meta = Join-Path ([IO.Path]::GetTempPath()) 'lazybicep-guide-meta.yaml'
$subtitle = ''
if ($titleParts.Count -gt 1) { $subtitle = $titleParts[1] }
$yaml = @(
    "title: '$($titleParts[0] -replace "'", "''")'"
    "subtitle: '$($subtitle -replace "'", "''")'"
    "author: 'Netmedia · version $($kit.version)'"
    "date: '$(Get-Date -Format 'yyyy-MM-dd')'"
    "toc-title: 'Table of contents'"
    'abstract: |'
    "  $abstract"
) -join "`n"
[IO.File]::WriteAllText($meta, $yaml, (New-Object Text.UTF8Encoding $false))

Push-Location $docs
try {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue' # pandoc warns on stderr
    & pandoc $body -f markdown -o $docx "--reference-doc=$ref" "--metadata-file=$meta" --resource-path=. --toc --toc-depth=2 --shift-heading-level-by=-1 2>&1 | ForEach-Object { Write-Host "  pandoc: $_" -ForegroundColor DarkGray }
    $ErrorActionPreference = $prev
} finally { Pop-Location; Remove-Item $body, $meta, $ref -ErrorAction SilentlyContinue }
if (-not (Test-Path $docx)) { throw 'pandoc wrote no document' }

# Word: the template's finishing touches; stopped if it hangs.
$before = @(Get-Process WINWORD -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
$word = New-Object -ComObject Word.Application
$mine = @(Get-Process WINWORD -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.Id } | ForEach-Object { $_.Id })
$guard = Start-Job -ScriptBlock { param($ids) Start-Sleep 240; foreach ($i in $ids) { Stop-Process -Id $i -Force -ErrorAction SilentlyContinue } } -ArgumentList (, $mine)
function Get-Style($Doc, [string]$Name) { try { return $Doc.Styles.Item($Name) } catch { return $null } }
try {
    $word.Visible = $false
    $word.DisplayAlerts = 0
    $d = $word.Documents.Open($docx, $false, $false, $false)
    # Every chapter on a new page (Heading 1: built-in style -2).
    $d.Styles.Item(-2).ParagraphFormat.PageBreakBefore = -1
    # Code blocks: Consolas 9 pt on grey (the theme's code; inline code has its style from the reference).
    $s = Get-Style $d 'Source Code'
    if ($s) {
        $s.Font.Name = 'Consolas'
        $s.Font.Size = 9
        $s.ParagraphFormat.Shading.BackgroundPatternColor = 0xF2F2F2
        $s.ParagraphFormat.LeftIndent = 6
        $s.ParagraphFormat.SpaceAfter = 6
    }
    # Tables: the template's Table Grid, 10 pt, a bold header row repeated on every page, as wide as the text.
    foreach ($t in $d.Tables) {
        try { $t.Style = 'Table Grid' } catch { $t.Borders.Enable = -1 }
        $t.Range.Font.Size = 10
        $t.Rows.Item(1).Range.Font.Bold = -1
        $t.Rows.Item(1).HeadingFormat = -1
        $t.AutoFitBehavior(2)
    }
    # The cover: the logo above the title (the theme: 16 mm).
    $first = $d.Paragraphs.Item(1).Range
    $first.InsertParagraphBefore()
    $pic = $d.InlineShapes.AddPicture($logo, $false, $true, $d.Paragraphs.Item(1).Range)
    $pic.LockAspectRatio = -1
    $pic.Height = 45.35
    $d.Paragraphs.Item(1).SpaceAfter = 36
    # A table cell's escaped pipe (GitHub's \| in the guide) stays escaped in pandoc's code: a plain | here.
    [void]$d.Content.Find.Execute('\|', $false, $false, $false, $false, $false, $true, 1, $false, '|', 2)
    # The fonts in the file: Montserrat shows without being installed.
    $d.EmbedTrueTypeFonts = $true
    $d.SaveSubsetFonts = $true
    foreach ($toc in $d.TablesOfContents) { $toc.Update() }
    $d.Save()
    if ($Pdf) { $d.ExportAsFixedFormat([IO.Path]::GetFullPath($Pdf), 17); Write-Host "  $Pdf" -ForegroundColor Green }
    $d.Close()
    Write-Host "  $docx" -ForegroundColor Green
} finally {
    try { $word.Quit() } catch { }
    Stop-Job $guard -ErrorAction SilentlyContinue
    Remove-Job $guard -Force -ErrorAction SilentlyContinue
}
