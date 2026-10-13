---
archetype: Conceptual
title: Looking Up Properly
subtitle: The celestial sphere, altitude and azimuth, and the sky seen from the equator
prior: "Light and Fields, module 07 (the spectrum) and How Things Move, module 00 (measuring)"
course: astro-sky-cosmos
index: 0
version: 1.0.0
---

# Looking Up Properly

The celestial sphere, altitude and azimuth, and the sky seen from the equator

## ORIENT · Sky As Sphere

**Prior:** Light and Fields, module 07, for light travelling in straight lines, and How Things Move, module 00, for measuring with a unit and an uncertainty. You need nothing else to begin: a clear horizon and your own two eyes are enough.

**Outcome:** describe any object's position in the sky with two angles, read those angles from your hand and from a phone, explain why the stars turn at 15 degrees an hour, and say what is special about the sky from Nairobi, which sits almost on the equator.

**Place:** astro-sky-cosmos, module 00 of 11.

## GRASP · Two Angles Suffice

Every object in the sky can be placed with two angles. Altitude is how high it stands above the horizon, from 0° at the horizon to 90° at the point overhead. Azimuth is the direction along the horizon, measured from north through east, so 90° is east, 180° is south and 270° is west. The stars look as if they sit on a huge dome turning around you, and for finding things that picture works very well, though the real distances differ by enormous factors. The turning is the Earth's own rotation seen from the inside.

## SEE · Fists Make Angles

**Story:** Hold your arm straight out and make a fist. The width of the fist covers about ten degrees of sky. Stack three fists from the horizon and the top one reaches an altitude near 30°. With a hand spread open, thumb tip to little finger tip, the span is about 20° to 25°. Your body gives you a ruler that comes with you everywhere.

The numbers hold up. A fist 9 cm wide, held 55 cm from the eye, covers 2 × arctan(4.5/55) = 9.35°. A thumb 2 cm wide at 65 cm covers 1.76°, about three and a half times the width of the Sun or Moon, each of which spans roughly half a degree. A thumb at arm's length is therefore a handy gauge for the Moon, which it covers more than three times over.

The dome turns. Over one night the stars sweep across the sky, each along a circle. The full circle takes one sidereal day, which is 23 hours 56 minutes and 4.0905 seconds, or 86,164.0905 s. The sidereal day is the time for the Earth to turn once relative to the stars. It is about four minutes shorter than the 24-hour solar day because during one turn the Earth also moves about 1° along its orbit, so it must turn slightly further for the Sun to return to the same place. The sky therefore turns by 360°/23.9345 h = 15.041° each hour, and a star that rises at a given time tonight rises about four minutes earlier tomorrow.

The pole holds still. The turning is around an axis, the line through the Earth's poles extended into space. The point where it meets the dome is the celestial pole, and the stars circle around it. Its altitude is always nearly equal to the observer's latitude. In Reykjavik at 64° the pole stands high in the northern sky. At the North Pole it is straight overhead. At the equator it sits on the horizon.

Nairobi is at 1.286° S. The south celestial pole therefore stands 1.286° above the southern horizon, and the north celestial pole lies 1.286° below the northern one. Every star rises and sets on a path nearly at right angles to the horizon, and the sky turns like a wheel standing on its edge. Over a year almost the entire sphere passes overhead. Only a cap within 1.286° of the north celestial pole never rises, and a cap of the same size around the south pole never sets. Each cap is (1 − cos 1.286°)/2 = 0.0126% of the sphere, so a patient observer at Nairobi sees 99.987% of the sky at some time of year, nearly all of it.

The Sun follows the same rule. At the equinox it rises due east (azimuth 90.2° on 20 March 2026) and sets due west, climbing steeply. On the June solstice it rises at azimuth 66.6°, to the north of east, and on the December solstice at 113.5°, to the south of east. Day length hardly changes: 12.035 hours on 21 June 2026, 12.097 on the March equinox and 12.188 on 21 December. Sunrise is about 06:20 to 06:40 in Nairobi, and sunset about 18:25 to 18:45, all year.

*Provenance: all values in this module were computed by a short script on 2 October 2026 (node, using the astronomy-engine library version 2.1.19, MIT licence, for Nairobi at 1.286° S, 36.817° E, 1,660 m). It printed sunrise azimuths 90.2°, 66.6° and 113.5°; day lengths 12.097, 12.035, 12.097 and 12.188 hours for 20 March, 21 June, 23 September and 21 December 2026; the fist angle 9.35°; the thumb angle 1.76°; the cap fraction 0.000126; and the rate 15.041° per hour.*

**Point:** two angles place any object in the sky, the whole dome turns at 15° an hour about a pole whose height equals your latitude, and the equator is where that pole lies on the horizon.

## BUILD · Altitude Azimuth Pole

**Concept:** Altitude and azimuth. These are local coordinates, tied to your horizon. They change as the sky turns, and they differ from place to place. The altitude of the object that is straight overhead is 90°, and that point is the zenith.

Celestial sphere. The sky is treated as a sphere of very large radius centred on you. The celestial equator is the Earth's equator projected out, and the celestial poles are the Earth's poles projected out. Each star has a fixed place on this sphere for everyday purposes, so its position is stated with two angles that do not change as the Earth turns: declination, measured north or south of the celestial equator, and right ascension, measured around it.

Latitude and the pole. The altitude of the celestial pole above the horizon is always nearly equal to the observer's geographic latitude. This is a result of geometry: the pole lies along the Earth's axis, and the angle between the axis and your horizontal plane depends only on how far north or south you stand. A traveller who finds the pole's altitude has found their latitude.

What is visible. A star with declination δ rises and sets for an observer at latitude φ if |δ| < 90° − |φ|. At the equator that is every star, so the whole sky is seen over a year. In Nairobi, with |φ| = 1.286°, the exceptions are the two tiny caps around the poles.

Why the sky turns. The Earth turns eastward once per sidereal day, so the sky seems to turn westward. Stars rise in the east, climb, cross the meridian (the north-south line through the zenith) and set in the west. Near the equator every path crosses the horizon almost vertically, so the Sun rises and sets at a steep angle and spends little time near the horizon.

```experiment
title: "Calibrate your fist as an angle"
tool: phyphox
link: https://phyphox.org/experiment/inclination/
experiment: inclination
sensor: accelerometer
materials: [a phone with phyphox installed, a ruler or tape measure, an open view of a flat horizon or a distant roofline]
steps:
  - Stand with your arm straight out and measure the distance from your eye to your fist in centimetres, then measure the width of your fist across the knuckles.
  - Compute the fist's angle as 2 x arctan(half the width / the distance) and note it.
  - Open the phyphox experiment "Inclination" and hold the phone's long edge level against your eye line so that it reads 0 degrees at the horizon.
  - Place one fist at the horizon, then tilt the phone to sight the top edge of the fist and read the inclination.
  - Repeat with two fists stacked and note whether the reading is twice as large.
measure: "fist width and eye distance in centimetres, the computed angle in degrees, and the phone inclination for one fist and for two stacked fists"
expected:
  value: 9.4
  low: 8
  high: 11
  derivation: "A fist 9 cm wide held 55 cm from the eye covers 2 x arctan(4.5 / 55) = 9.35 degrees. The phone reading for one fist should come out close to your own computed value, and the reading for two fists close to twice that. The range of about 15 percent allows for hand size, arm length and the difficulty of holding the phone steady."
safety: "Do not look at the Sun, even with a fist or a phone in the way, and sight only along a clear horizon where you will not trip."
reflect: "How many fists tall is the sky from horizon to zenith, and why does the answer change from person to person?"
```

**Fact:** A sidereal day is 23 hours, 56 minutes and 4.0905 seconds (about 86,164.0905 seconds), shorter than the solar day because the Earth moves about 1° along its orbit during one rotation and must turn slightly further for the Sun to return to local noon.
Sidereal time. (2026, October 2). In *Wikipedia*. https://en.wikipedia.org/wiki/Sidereal_time

**Fact:** The altitude angle of the celestial pole is always (nearly) equal to the observer's geographic latitude.
Celestial pole. (2026, October 2). In *Wikipedia*. https://en.wikipedia.org/wiki/Celestial_pole

## PROBE · Pole And Fists

**Probe:** At what altitude does the south celestial pole stand in Nairobi, and in Cape Town at 33.9° S? Then find how many fists tall a star at altitude 45° stands, and how many degrees the sky turns in 3 hours.

## GUARD · Dome Is Convenient

**Failure:** Treating the dome as real. The stars are at wildly different distances, from a few light-years to billions, and the sphere is only a way of recording directions. A second error is to think the pole star marks the pole everywhere. Polaris is close to the north celestial pole, which lies 1.286° below the horizon at Nairobi, so Polaris is out of sight for practical purposes. A third error is to think the stars turn because they move. The Earth turns, and the stars are carried across the sky by that turning.

**Pitfalls:**
- **Mixing altitude and azimuth.** One is height, the other is direction.
- **Using the solar day for the stars.** A star returns to the same place in 23 h 56 min.
- **Trusting the fist on a different hand.** Calibrate your own with a measured distance.

## MASTER · Reference Frames Matter

Experts start every observation by stating the frame. Altitude and azimuth belong to this place and this moment, right ascension and declination belong to the sky, and the conversion between them uses the time and the latitude. They carry a small calibration: a fist, a hand, a finger. They plan observing around the turning of the dome, because an object that is high at 21:00 tonight is high at about 20:56 tomorrow. And they use the equator's special property, that the whole sky passes overhead in a year, as a reason to observe from it.

**Link:** Module 01 follows the Sun through the year, using the altitude it reaches at noon. Module 07 uses the same angles to find the distance of a landmark by parallax.

## APPLY · Measure With Hands

1. **Now:** Hold out a fist and find how many fists fit between the horizon and the zenith. The usual answer is nine.
2. **Week:** Pick one bright star and note its position in fists and compass direction at the same time on three evenings. Keep the notes.
3. **Role:** Use altitude and azimuth to tell someone else where an object is, instead of pointing.
4. **Model:** From horizon to zenith is 90°, and with a fist of 9.4° the sky is 9.6 fists tall. A star seen two fists above the eastern horizon is at altitude 19° and azimuth 90°.
5. **Proof:** Your star is about 3° further west three days later at the same clock time, since it rises about four minutes earlier each day, and 12 minutes of turning is 3°.

## ANCHOR · Keep The Frame

**Essentials:**
- Altitude is height above the horizon, and azimuth is the compass direction.
- A fist at arm's length is about 10°.
- The sky turns once per sidereal day, 23 h 56 min 4.09 s, which is 15.04° per hour.
- The altitude of the celestial pole equals your latitude.
- In Nairobi the poles sit almost on the horizon and 99.987% of the sky is visible over a year.

**Check:**
1. What is the azimuth of due west?
2. By how many minutes earlier does a star rise each day?
3. At what altitude is the south celestial pole in Nairobi?
4. Why do the Sun and stars rise almost vertically at the equator?
5. How wide is a thumb at arm's length in degrees, and why is that useful?

**Return:** In a month, find north, south and a star's altitude in fists without a phone.
