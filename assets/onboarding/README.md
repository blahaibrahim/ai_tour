# Onboarding artwork

Drop the intro illustrations in here. No code change is needed — each slide
already points at its file, and `OnboardingArt` swaps the stand-in for the real
image as soon as one exists at the expected path.

| File | Slide | Subject | Layout |
| --- | --- | --- | --- |
| `01_welcome.png` | This is Massar | The opener — fennec / compass branding | art, title, body |
| `02_routes_tasks.png` | A route built around you | A route drawn through a city, with a task marked at a stop on it | title, art, body |
| `03_camera.png` | Catch fennecs, keep souvenirs | A phone held up: a fennec on one side of the frame, an object resolving into a 3D model on the other | title, body, art |
| `04_rewards.png` | Turn your points into something real | Points being redeemed | art, title, body |

Two of these carry two ideas each, so they need art that shows both rather than
one subject with the other implied — slide 2 is the route *and* the task on it,
slide 3 is the hunt *and* the scanner.

Notes for whoever draws these:

- **Transparent PNGs.** There is no frame, border or fill behind the art — it
  sits directly on the page, so anything with a baked-in white background will
  read as a pasted-on rectangle.
- The page background is a near-vertical wash with no white in it, running from
  fennec sand (`#F8D59B`) at the top through a warm greige crossover
  (`#DED6C8`) to a soft compass blue (`#9CB0D6`) at the bottom. It gets steadily
  darker top to bottom — there is no bright band anywhere — so art has to hold
  up on a tinted ground, and against whichever end its layout puts it near:
  slides 1 and 4 lead with their art, so it sits over the sand, while slide 3's
  art trails the text and sits over the blue.
- The slot letterboxes rather than crops (`BoxFit.contain`), so nothing near
  the edges gets cut, but art filling a 4:3 or 1:1 frame uses the space best.
- The art's share of the page height varies by layout: 46% when it leads, 42%
  when it trails, 36% when it sits between the title and the body.
- A different extension is fine (`.webp`, `.jpg`); update the `artAsset` paths
  in `lib/screens/onboarding/onboarding_content.dart` to match.

The whole directory is registered in `pubspec.yaml`, so new files are picked up
by a normal `flutter run` — no `pubspec` edit, just a restart.
