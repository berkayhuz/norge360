param(
    [string]$InputDir = (Join-Path $PSScriptRoot "..\BenchmarkDotNet.Artifacts\results"),
    [string]$OutputFile = (Join-Path $PSScriptRoot "..\BenchmarkDotNet.Artifacts\results\reports.html")
)

$ErrorActionPreference = "Stop"

$resolvedInput = (Resolve-Path $InputDir).Path
$outputDir = Split-Path -Parent $OutputFile
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$csvFiles = Get-ChildItem -Path $resolvedInput -Filter "*-report.csv" -File | Sort-Object Name
if (-not $csvFiles -or $csvFiles.Count -eq 0) {
    throw "No benchmark report CSV files found in '$resolvedInput'."
}

$rows = foreach ($file in $csvFiles) {
    $items = Import-Csv -Path $file.FullName -Delimiter ";"
    foreach ($item in $items) {
        [PSCustomObject]@{
            ReportFile = $file.Name
            Method     = $item.Method
            Mean       = $item.Mean
            Error      = $item.Error
            StdDev     = $item.StdDev
            Median     = $item.Median
            Allocated  = $item.Allocated
            Gen0       = $item.Gen0
            Job        = $item.Job
            Runtime    = $item.Runtime
        }
    }
}

$rows = $rows | Sort-Object ReportFile, Method

$style = @"
body { font-family: Segoe UI, Arial, sans-serif; margin: 24px; background: #fafafa; color: #1f2937; }
h1 { margin-bottom: 8px; }
p.meta { margin-top: 0; color: #4b5563; }
input { padding: 8px; width: 360px; max-width: 100%; margin-bottom: 12px; border: 1px solid #d1d5db; border-radius: 6px; }
table { border-collapse: collapse; width: 100%; background: white; }
th, td { border: 1px solid #e5e7eb; padding: 8px 10px; text-align: left; font-size: 13px; }
th { position: sticky; top: 0; background: #f3f4f6; }
tr:nth-child(even) { background: #f9fafb; }
.wrap { overflow-x: auto; border: 1px solid #e5e7eb; border-radius: 8px; }
"@

$header = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Benchmark Reports</title>
  <style>$style</style>
</head>
<body>
  <h1>Benchmark Reports</h1>
  <p class="meta">Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss") | Files: $($csvFiles.Count) | Rows: $($rows.Count)</p>
  <input id="q" type="text" placeholder="Filter (method, report file, runtime, job...)" />
  <div class="wrap">
"@

$table = $rows | ConvertTo-Html -Fragment -Property ReportFile, Method, Mean, Error, StdDev, Median, Allocated, Gen0, Job, Runtime

$footer = @"
  </div>
  <script>
    const q = document.getElementById('q');
    const rows = Array.from(document.querySelectorAll('table tr')).slice(1);
    q.addEventListener('input', function () {
      const term = this.value.toLowerCase();
      rows.forEach(r => {
        const t = r.textContent.toLowerCase();
        r.style.display = t.includes(term) ? '' : 'none';
      });
    });
  </script>
</body>
</html>
"@

$html = $header + $table + $footer
Set-Content -Path $OutputFile -Value $html -Encoding UTF8

Write-Host "Merged $($rows.Count) rows from $($csvFiles.Count) files."
Write-Host "Output: $OutputFile"
