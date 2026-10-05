param([string]$Path,[int]$X,[int]$Y,[int]$W,[int]$H,[int]$Thresh=160,[switch]$Rows)
Add-Type -AssemblyName System.Drawing
$img=New-Object System.Drawing.Bitmap($Path)
$img=$img.Clone((New-Object System.Drawing.Rectangle $X,$Y,$W,$H),$img.PixelFormat)
$inkRows=New-Object System.Collections.ArrayList
$minX=999999;$maxX=-1;$minY=999999;$maxY=-1
for($yy=0;$yy -lt $H;$yy++){
  $cnt=0
  for($xx=0;$xx -lt $W;$xx++){
    $c=$img.GetPixel($xx,$yy)
    $lum=($c.R*0.299+$c.G*0.587+$c.B*0.114)
    if($lum -lt $Thresh){$cnt++; if($xx -lt $minX){$minX=$xx}; if($xx -gt $maxX){$maxX=$xx}; if($yy -lt $minY){$minY=$yy}; if($yy -gt $maxY){$maxY=$yy}}
  }
  if($Rows){ [void]$inkRows.Add("$($Y+$yy)`t$cnt") }
}
"region=[$X,$Y][$($X+$W),$($Y+$H)] inkX=[$($X+$minX)..$($X+$maxX)] inkY=[$($Y+$minY)..$($Y+$maxY)] inkH=$($maxY-$minY+1) inkW=$($maxX-$minX+1)"
if($Rows){ $inkRows | Where-Object { [int]($_ -split "`t")[1] -gt 0 } }
$img.Dispose()
