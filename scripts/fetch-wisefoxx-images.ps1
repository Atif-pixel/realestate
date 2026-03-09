param(
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function Get-JpegEncoder {
  return [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' } | Select-Object -First 1
}

function Save-Jpeg {
  param(
    [Parameter(Mandatory)] [System.Drawing.Image]$Image,
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [int]$Quality
  )

  $encoder = Get-JpegEncoder
  if (-not $encoder) { throw "JPEG encoder not found." }

  $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
  $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$Quality)

  $Image.Save($Path, $encoder, $encoderParams)
}

function Resize-Image {
  param(
    [Parameter(Mandatory)] [System.Drawing.Image]$Image,
    [Parameter(Mandatory)] [int]$MaxWidth
  )

  if ($Image.Width -le $MaxWidth) { return New-Object System.Drawing.Bitmap($Image) }

  $scale = $MaxWidth / [double]$Image.Width
  $newWidth = [int][math]::Round($Image.Width * $scale)
  $newHeight = [int][math]::Round($Image.Height * $scale)

  $bitmap = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
  $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
  $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $graphics.DrawImage($Image, 0, 0, $newWidth, $newHeight)
  $graphics.Dispose()

  return $bitmap
}

function Optimize-JpegToTarget {
  param(
    [Parameter(Mandatory)] [string]$Path,
    [Parameter(Mandatory)] [int]$MaxWidth,
    [int]$TargetBytes = 307200,
    [int]$StartQuality = 82,
    [int]$MinQuality = 62,
    [int]$MinWidth = 1400
  )

  $tempPath = "$Path.__tmp.jpg"

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $memoryStream = New-Object System.IO.MemoryStream(,$bytes)
  $original = [System.Drawing.Image]::FromStream($memoryStream)
  try {
    $currentWidth = $MaxWidth

    while ($true) {
      $working = Resize-Image -Image $original -MaxWidth $currentWidth
      try {
        $quality = $StartQuality
        while ($true) {
          if (Test-Path $tempPath) { Remove-Item -Force $tempPath }
          Save-Jpeg -Image $working -Path $tempPath -Quality $quality

          $bytes = (Get-Item $tempPath).Length
          if ($bytes -le $TargetBytes) {
            Move-Item -Force $tempPath $Path
            return
          }

          if ($quality -le $MinQuality) { break }
          $quality -= 6
        }
      }
      finally {
        $working.Dispose()
      }

      if ($currentWidth -le $MinWidth) {
        Move-Item -Force $tempPath $Path
        return
      }

      $currentWidth = [int][math]::Round($currentWidth * 0.85)
      if ($currentWidth -lt $MinWidth) { $currentWidth = $MinWidth }
    }
  }
  finally {
    $original.Dispose()
    $memoryStream.Dispose()
  }
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$imageDir = Join-Path $projectRoot 'images'
New-Item -ItemType Directory -Force -Path $imageDir | Out-Null

$images = @(
  @{
    File = 'hero-gradeA-office.jpg'
    Url  = 'https://unsplash.com/photos/V_yQ8IyCmYY/download?force=true'
    MaxWidth = 2400
  },
  @{
    File = 'service-office-leasing.jpg'
    Url  = 'https://unsplash.com/photos/TuHevCS88q0/download?force=true'
    MaxWidth = 2400
  },
  @{
    File = 'service-coworking.jpg'
    Url  = 'https://unsplash.com/photos/VCoh27vHEh0/download?force=true'
    MaxWidth = 2400
  },
  @{
    File = 'service-preleased-bank.jpg'
    Url  = 'https://unsplash.com/photos/nc5NrVH5Vc8/download?force=true'
    MaxWidth = 2400
  },
  @{
    File = 'trust-experience.jpg'
    Url  = 'https://unsplash.com/photos/xG-s4Ng3_hY/download?force=true'
    MaxWidth = 2200
  },
  @{
    File = 'process-negotiation.jpg'
    Url  = 'https://unsplash.com/photos/wRbe-OAIxNc/download?force=true'
    MaxWidth = 2200
  },
  @{
    File = 'pune-skyline.jpg'
    Url  = 'https://unsplash.com/photos/TwZFaDuGyeA/download?force=true'
    MaxWidth = 2400
  }
)

foreach ($item in $images) {
  $outPath = Join-Path $imageDir $item.File
  if ((-not $Force) -and (Test-Path $outPath)) {
    Write-Host "Skip (exists): $($item.File)"
    continue
  }

  $downloadPath = "$outPath.__download"
  if (Test-Path $downloadPath) { Remove-Item -Force $downloadPath }

  Write-Host "Download: $($item.File)"
  Invoke-WebRequest -Uri $item.Url -OutFile $downloadPath

  if (Test-Path $outPath) { Remove-Item -Force $outPath }
  Move-Item -Force $downloadPath $outPath

  Write-Host "Optimize: $($item.File)"
  Optimize-JpegToTarget -Path $outPath -MaxWidth $item.MaxWidth
}

Write-Host "Done. Sources: $([IO.Path]::Combine($imageDir, 'WISEFOXX-IMAGE-SOURCES.md'))"
