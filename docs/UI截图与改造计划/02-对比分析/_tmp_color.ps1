param([string]$Path,[int]$X,[int]$Y,[int]$W,[int]$H,[int]$N=6,[string]$Label="")
Add-Type -AssemblyName System.Drawing
$img=New-Object System.Drawing.Bitmap($Path)
$list=New-Object System.Collections.ArrayList
for($y=$Y;$y -lt ($Y+$H);$y++){
  for($x=$X;$x -lt ($X+$W);$x++){
    $p=$img.GetPixel($x,$y)
    $l=($p.R*0.299+$p.G*0.587+$p.B*0.114)
    [void]$list.Add([pscustomobject]@{x=$x;y=$y;r=$p.R;g=$p.G;b=$p.B;l=$l})
  }
}
"--- $Label ($Path) region [$X,$Y][$($X+$W),$($Y+$H)] ---"
"darkest ${N}:"

$list | Sort-Object l | Select-Object -First $N | ForEach-Object { "  ($($_.x),$($_.y)) rgb=$($_.r),$($_.g),$($_.b) #$('{0:X2}{1:X2}{2:X2}' -f $_.r,$_.g,$_.b) lum=$([int]$_.l)" }
"most saturated (max-min channel spread):"
$list | Sort-Object { -($_.r-$_.b) } | Select-Object -First $N | ForEach-Object { "  ($($_.x),$($_.y)) rgb=$($_.r),$($_.g),$($_.b) #$('{0:X2}{1:X2}{2:X2}' -f $_.r,$_.g,$_.b)" }
$img.Dispose()
