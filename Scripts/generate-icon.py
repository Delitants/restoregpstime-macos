#!/usr/bin/env python3
"""Original clock-and-location artwork. Pillow is an authoring dependency only."""
from pathlib import Path
from PIL import Image, ImageDraw
import math

root=Path(__file__).resolve().parent.parent
size=2048
image=Image.new('RGBA',(size,size),(0,0,0,0))
d=ImageDraw.Draw(image)
s=2
# A quiet blue rounded tile, with a clock face and a separate location marker.
d.rounded_rectangle((112*s,112*s,912*s,912*s),radius=180*s,fill=(24,92,172,255))
d.rounded_rectangle((132*s,132*s,892*s,892*s),radius=160*s,outline=(104,175,232,255),width=3*s)
d.ellipse((246*s,220*s,778*s,752*s),outline=(245,250,255,255),width=30*s)
for n in range(12):
 a=n*math.pi/6
 x,y=512+230*math.sin(a),486-230*math.cos(a)
 xx,yy=512+209*math.sin(a),486-209*math.cos(a)
 d.line((x*s,y*s,xx*s,yy*s),fill=(225,242,255,255),width=7*s)
d.line((512*s,324*s,512*s,486*s,623*s,549*s),fill=(255,255,255,255),width=30*s)
d.ellipse((493*s,467*s,531*s,505*s),fill=(255,255,255,255))
# The pin stands to the lower right so the clock hands remain readable at small sizes.
d.polygon([(653*s,673*s),(805*s,673*s),(729*s,833*s)],fill=(121,230,213,255))
d.ellipse((638*s,550*s,820*s,732*s),fill=(121,230,213,255))
d.ellipse((686*s,598*s,772*s,684*s),fill=(24,92,172,255))
resources=root/'App/Resources'
image.resize((1024,1024),Image.Resampling.LANCZOS).save(resources/'AppIcon.png')
image.resize((1024,1024),Image.Resampling.LANCZOS).save(resources/'AppIcon.icns',format='ICNS')
