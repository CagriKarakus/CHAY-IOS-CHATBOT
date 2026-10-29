<#
.SYNOPSIS
Faz 0: LLM endpoint'inin OpenAI-uyumlu olduğunu ve tool calling desteklediğini doğrular.
Streaming yanıtları AgentCore testleri için fixture olarak kaydeder.

.EXAMPLE
$env:LLM_BASE_URL = "https://router.example.com/v1"   # /v1 dahil
$env:LLM_API_KEY  = "<key>"
.\scripts\faz0.ps1 -Model "model-adi"
#>
param([Parameter(Mandatory = $true)][string]$Model)

$ErrorActionPreference = "Stop"

if (-not $env:LLM_BASE_URL -or -not $env:LLM_API_KEY) {
    throw "Önce LLM_BASE_URL ve LLM_API_KEY ortam değişkenlerini ayarla."
}

$base = $env:LLM_BASE_URL.TrimEnd("/")
$auth = "Authorization: Bearer $($env:LLM_API_KEY)"
$fixtures = Join-Path $PSScriptRoot "..\Packages\AgentCore\Tests\AgentCoreTests\Fixtures"
New-Item -ItemType Directory -Force $fixtures | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false

$weatherTool = @{
    type     = "function"
    function = @{
        name        = "get_weather"
        description = "Bir şehrin güncel hava durumunu döndürür."
        parameters  = @{
            type       = "object"
            properties = @{ city = @{ type = "string" } }
            required   = @("city")
        }
    }
}

function Invoke-Chat([string]$Prompt, [bool]$Stream, [bool]$WithTools, [string]$OutFile) {
    $body = @{
        model    = $Model
        stream   = $Stream
        messages = @(@{ role = "user"; content = $Prompt })
    }
    if ($WithTools) { $body.tools = @($weatherTool) }

    $tmp = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmp, ($body | ConvertTo-Json -Depth 10), $utf8)
    try {
        $curlArgs = @("-sS", "-N", "--fail-with-body", "$base/chat/completions",
                  "-H", $auth, "-H", "Content-Type: application/json",
                  "--data-binary", "@$tmp")
        if ($OutFile) { $curlArgs += @("-o", $OutFile) }
        $out = & curl.exe @curlArgs | Out-String
        if ($LASTEXITCODE -ne 0) { throw "İstek başarısız (curl çıkış kodu $LASTEXITCODE):`n$out" }
        if ($OutFile) { return [System.IO.File]::ReadAllText($OutFile) }
        return $out
    } finally {
        Remove-Item $tmp -ErrorAction SilentlyContinue
    }
}

Write-Host "== 1/4 Model listesi ==" -ForegroundColor Cyan
$models = & curl.exe -sS --fail-with-body "$base/models" -H $auth | Out-String
if ($LASTEXITCODE -ne 0) { throw "Model listesi alınamadı:`n$models" }
$models

Write-Host "== 2/4 Tool calling (streaming yok) ==" -ForegroundColor Cyan
$plain = Invoke-Chat "İstanbul'da hava nasıl? get_weather aracını kullan." $false $true $null
$plain
$toolsOk = $plain -match '"tool_calls"'

Write-Host "== 3/4 Streaming metin -> Fixtures\text-stream.sse ==" -ForegroundColor Cyan
$textFile = Join-Path $fixtures "text-stream.sse"
$text = Invoke-Chat "Bir cümleyle kendini tanıt." $true $false $textFile
$streamOk = $text -match 'data: \[DONE\]'

Write-Host "== 4/4 Streaming tool call -> Fixtures\tool-call-stream.sse ==" -ForegroundColor Cyan
$toolFile = Join-Path $fixtures "tool-call-stream.sse"
$toolStream = Invoke-Chat "İstanbul'da hava nasıl? get_weather aracını kullan." $true $true $toolFile
$streamToolsOk = $toolStream -match '"tool_calls"'

Write-Host ""
Write-Host "Sonuç:" -ForegroundColor Cyan
Write-Host ("  tool_calls (normal)    : " + $(if ($toolsOk) { "EVET" } else { "HAYIR" }))
Write-Host ("  streaming + [DONE]     : " + $(if ($streamOk) { "EVET" } else { "HAYIR" }))
Write-Host ("  tool_calls (streaming) : " + $(if ($streamToolsOk) { "EVET" } else { "HAYIR" }))
if (-not ($toolsOk -and $streamOk -and $streamToolsOk)) {
    Write-Warning "Faz 0 doğrulaması geçmedi; bu model/router ile araç kullanımı sorunlu olabilir."
    exit 1
}
Write-Host "Faz 0 geçti. Fixture'ları commit etmeden önce içlerinde kişisel veri olmadığını kontrol et." -ForegroundColor Green
