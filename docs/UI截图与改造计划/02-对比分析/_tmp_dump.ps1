param([string]$Path,[string]$Filter="",[string]$Type="",[int]$Max=200,[switch]$NoText)
$t=[System.IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
$ms=[regex]::Matches($t,'"attributes":\{[^{}]*\}')
$out=New-Object System.Collections.ArrayList
foreach($m in $ms){
  $s=$m.Value
  $h=@{}
  foreach($kv in [regex]::Matches($s,'"([A-Za-z0-9_]+)":"((?:[^"\\]|\\.)*)"')){
    $h[$kv.Groups[1].Value]=$kv.Groups[2].Value
  }
  $b=$h['bounds']; $txt=$h['text']; $ty=$h['type']
  if($null -eq $txt){$txt=''}
  if($NoText -and $txt -eq ''){continue}
  if($Filter -ne "" -and ($txt -notlike "*$Filter*")){continue}
  if($Type -ne "" -and $ty -ne $Type){continue}
  $bc=$h['backgroundColor']
  [void]$out.Add(("{0,-14} | {1,-22} | bg={2,-10} | {3}" -f $ty,$b,$bc,$txt))
}
$out | Select-Object -First $Max
"### total matched: $($out.Count)"
