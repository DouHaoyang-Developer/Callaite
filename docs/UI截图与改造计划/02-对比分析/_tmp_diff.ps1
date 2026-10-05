param([string]$A,[string]$B,[int]$Thresh=24)
Add-Type -AssemblyName System.Drawing
$ia=New-Object System.Drawing.Bitmap($A)
$ib=New-Object System.Drawing.Bitmap($B)
"$([IO.Path]::GetFileName($A)) = $($ia.Width)x$($ia.Height) ; $([IO.Path]::GetFileName($B)) = $($ib.Width)x$($ib.Height)"
$w=[Math]::Min($ia.Width,$ib.Width); $h=[Math]::Min($ia.Height,$ib.Height)
$minX=999999;$maxX=-1;$minY=999999;$maxY=-1;$cnt=0
$colHist=@{}
for($y=0;$y -lt $h;$y++){
  for($x=0;$x -lt $w;$x++){
    $ca=$ia.GetPixel($x,$y); $cb=$ib.GetPixel($x,$y)
    $d=[Math]::Abs($ca.R-$cb.R)+[Math]::Abs($ca.G-$cb.G)+[Math]::Abs($ca.B-$cb.B)
    if($d -gt $Thresh){
      $cnt++
      if($x -lt $minX){$minX=$x}; if($x -gt $maxX){$maxX=$x}
      if($y -lt $minY){$minY=$y}; if($y -gt $maxY){$maxY=$y}
      $band=[int]($x/100)*100
      if($colHist.ContainsKey($band)){$colHist[$band]++}else{$colHist[$band]=1}
    }
  }
}
"diffPixels=$cnt  bbox=[$minX,$minY][$maxX,$maxY]"
"x-band histogram (band=100px):"
$colHist.GetEnumerator() | Sort-Object {[int]$_.Key} | ForEach-Object { "  x $($_.Key)-$([int]$_.Key+99) : $($_.Value)" }
$ia.Dispose();$ib.Dispose()
