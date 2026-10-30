# Checks how OpenRouter's built-in tools answer, for the parts its docs don't spell out.
# Your key stays in this terminal. Nothing is saved except a temporary request file.
#
#   $env:OPENROUTER_API_KEY = "<key>"
#   powershell -ExecutionPolicy Bypass -File scripts\router-check.ps1
#
# It makes two paid requests: one web search and one small image.
param(
    [string]$Model = "openai/gpt-4o-mini"
)

$key = $env:OPENROUTER_API_KEY
if (-not $key) {
    Write-Host "Set OPENROUTER_API_KEY first." -ForegroundColor Red
    exit 1
}

$url = "https://openrouter.ai/api/v1/chat/completions"
$bodyFile = Join-Path $env:TEMP "chay-router-check.json"

function Send-Request([string]$Body) {
    [System.IO.File]::WriteAllText($bodyFile, $Body)
    $curlArgs = @(
        "-s", "-m", "120", "-N", $url,
        "-H", "Authorization: Bearer $key",
        "-H", "Content-Type: application/json",
        "--data-binary", "@$bodyFile"
    )
    & curl.exe @curlArgs
}

function Shorten([string]$Text, [int]$Limit) {
    if ($Text.Length -le $Limit) { return $Text }
    return $Text.Substring(0, $Limit) + " ...[cut]"
}

Write-Host "`n=== 1. Web search (streaming) ===" -ForegroundColor Cyan
$search = '{"model":"' + $Model + '","stream":true,"stream_options":{"include_usage":true},"max_tool_calls":3,' +
    '"messages":[{"role":"user","content":"What is the latest stable Swift version? Answer in one sentence."}],' +
    '"tools":[{"type":"openrouter:web_search","parameters":{"max_results":3}}]}'
$lines = Send-Request $search
$lines | Where-Object { $_ -match 'annotations|server_tool_use|"error"|url_citation' } |
    Select-Object -Last 8 | ForEach-Object { Shorten $_ 900 }
Write-Host "--- other delta keys seen ---"
$lines | Where-Object { $_ -like 'data: {*' } | ForEach-Object {
    if ($_ -match '"delta":\{([^{]*)') { ($Matches[1] -replace '"[^"]*$', '').Substring(0, [Math]::Min(40, $Matches[1].Length)) }
} | Sort-Object -Unique | Select-Object -First 12

Write-Host "`n=== 2. Image generation (no streaming) ===" -ForegroundColor Cyan
$image = '{"model":"' + $Model + '","stream":false,' +
    '"messages":[{"role":"user","content":"Create a small simple icon of a tea glass."}],' +
    '"tools":[{"type":"openrouter:image_generation","parameters":{"quality":"low","size":"1024x1024"}}]}'
$answer = (Send-Request $image) -join "`n"
Shorten $answer 3000

Remove-Item $bodyFile -ErrorAction SilentlyContinue
Write-Host "`nDone. Copy everything above and send it to Claude." -ForegroundColor Green
