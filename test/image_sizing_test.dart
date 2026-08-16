import 'package:flutter_test/flutter_test.dart';
import 'package:massar/utils/image_sizing.dart';

/// Two real URLs out of tool/poi_seed/seed_pois.sql — one seeded thumbnail,
/// one untouched original — so the rewrite is exercised against the shapes the
/// catalogue actually contains rather than tidied-up examples.
const _thumb =
    'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/AlgerCasbah.jpg/1280px-AlgerCasbah.jpg';
const _original =
    'https://upload.wikimedia.org/wikipedia/commons/b/b5/Mus%C3%A9e_d%27art_moderne_d%27Alger.jpg';

void main() {
  group('imageWidthBucket', () {
    test('every bucket is a size Wikimedia will actually serve', () {
      // Wikimedia rejects direct requests for non-standard widths with HTTP 400
      // (T414805), so a bucket outside this set would break every photo at that
      // size. This is the guard on that.
      const standard = <int>[20, 40, 60, 120, 250, 330, 500, 960, 1280, 1920, 3840];
      for (final bucket in kImageWidthBuckets) {
        expect(standard, contains(bucket), reason: '$bucket is not a standard Wikimedia size');
      }
    });

    test('buckets are sorted ascending, as the lookup assumes', () {
      final sorted = [...kImageWidthBuckets]..sort();
      expect(kImageWidthBuckets, sorted);
    });

    test('rounds up to the next bucket', () {
      // A 56px list thumbnail on a 3x screen needs 168 real pixels.
      expect(imageWidthBucket(56, 3), 250);
      expect(imageWidthBucket(76, 3), 250);
      expect(imageWidthBucket(220, 3), 960);
    });

    test('returns a bucket exactly, not the measured width', () {
      expect(kImageWidthBuckets, contains(imageWidthBucket(137, 2.625)));
    });

    test('list and itinerary thumbnails share a bucket', () {
      // The point of bucketing: the same photo at 56px and at 76px must resolve
      // to one cached file, not two downloads.
      expect(imageWidthBucket(56, 3), imageWidthBucket(76, 3));
    });

    test('unbounded or degenerate widths fall back to the largest bucket', () {
      expect(imageWidthBucket(double.infinity, 3), 1280);
      expect(imageWidthBucket(0, 3), 1280);
      expect(imageWidthBucket(-10, 3), 1280);
    });

    test('never exceeds the largest bucket', () {
      expect(imageWidthBucket(2000, 4), 1280);
    });
  });

  group('sizedImageUrl on an existing thumbnail', () {
    test('narrows the width marker in place', () {
      expect(
        sizedImageUrl(_thumb, 250),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/AlgerCasbah.jpg/250px-AlgerCasbah.jpg',
      );
    });

    test('leaves a thumbnail that is already small enough alone', () {
      const small =
          'https://upload.wikimedia.org/wikipedia/commons/thumb/d/d4/AlgerCasbah.jpg/250px-AlgerCasbah.jpg';
      // Widening costs bytes and gains nothing but a cache miss.
      expect(sizedImageUrl(small, 960), small);
      expect(sizedImageUrl(small, 250), small);
    });

    test('preserves percent-encoding untouched', () {
      const encoded =
          'https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Djama%C3%A2_El_Djaza%C3%AFr.jpg/1280px-Djama%C3%A2_El_Djaza%C3%AFr.jpg';
      final out = sizedImageUrl(encoded, 500);
      expect(out, contains('Djama%C3%A2_El_Djaza%C3%AFr'));
      expect(out, endsWith('500px-Djama%C3%A2_El_Djaza%C3%AFr.jpg'));
      // Nothing should have been decoded and re-encoded along the way.
      expect(out, isNot(contains('â')));
    });

    test('handles a prefixed thumbnail name', () {
      const lossy =
          'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Foo.tif/lossy-page1-1280px-Foo.tif.jpg';
      expect(
        sizedImageUrl(lossy, 250),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/a/ab/Foo.tif/lossy-page1-250px-Foo.tif.jpg',
      );
    });
  });

  group('sizedImageUrl on an original', () {
    test('routes it through the thumbnailer when we want it much smaller', () {
      expect(
        sizedImageUrl(_original, 250),
        'https://upload.wikimedia.org/wikipedia/commons/thumb/b/b5/'
        'Mus%C3%A9e_d%27art_moderne_d%27Alger.jpg/'
        '250px-Mus%C3%A9e_d%27art_moderne_d%27Alger.jpg',
      );
    });

    test('leaves it alone at the large buckets', () {
      // Catalogue originals are web-sized already; re-rendering one at 960 or
      // 1280 tends to produce a bigger file than the one it replaces, and fails
      // outright when the original is narrower than the bucket.
      expect(sizedImageUrl(_original, 960), _original);
      expect(sizedImageUrl(_original, 1280), _original);
    });

    test('rasterises vector and document sources', () {
      expect(
        sizedImageUrl(
          'https://upload.wikimedia.org/wikipedia/commons/1/12/Flag.svg',
          500,
        ),
        endsWith('/Flag.svg/500px-Flag.svg.png'),
      );
      expect(
        sizedImageUrl(
          'https://upload.wikimedia.org/wikipedia/commons/1/12/Scan.tif',
          500,
        ),
        endsWith('/Scan.tif/500px-Scan.tif.jpg'),
      );
    });

    test('rewrite is detectable by the caller', () {
      // NetImage relies on this to know whether it has an original to fall back
      // to when the thumbnailer refuses the request.
      expect(sizedImageUrl(_original, 250), isNot(_original));
    });
  });

  group('sizedImageUrl leaves alone what it does not understand', () {
    test('non-Wikimedia hosts', () {
      // Supabase signed capture URLs in particular must pass through untouched.
      const supabase =
          'https://abc.supabase.co/storage/v1/object/sign/captures/u/a.jpg?token=x';
      expect(sizedImageUrl(supabase, 250), supabase);
    });

    test('a Wikimedia URL carrying a query string', () {
      const query =
          'https://upload.wikimedia.org/wikipedia/commons/b/b5/Foo.jpg?v=2';
      expect(sizedImageUrl(query, 250), query);
    });

    test('paths that are not a file layout', () {
      const odd = 'https://upload.wikimedia.org/wikipedia/commons/b/Foo.jpg';
      expect(sizedImageUrl(odd, 250), odd);
      const extensionless =
          'https://upload.wikimedia.org/wikipedia/commons/b/b5/Foo';
      expect(sizedImageUrl(extensionless, 250), extensionless);
    });

    test('empty input and nonsense widths', () {
      expect(sizedImageUrl('', 250), '');
      expect(sizedImageUrl(_thumb, 0), _thumb);
      expect(sizedImageUrl(_thumb, -1), _thumb);
    });
  });
}
