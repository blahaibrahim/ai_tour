import 'location.dart';

/// All regions the user can filter by.
const List<String> regions = [
  "Algiers & the Casbah",
  "Constantine",
  "Djemila & Timgad",
  "Tassili n'Ajjer / Sahara",
  "Kabylie mountains & coast"
];

/// The full catalogue of locations the app can suggest.
final List<Location> allLocations = [
  Location(
      id: "casbah",
      name: "Casbah of Algiers",
      region: "Algiers & the Casbah",
      category: "Old town",
      distanceKm: 2,
      blurb:
          "A UNESCO-listed maze of Ottoman-era alleys, tiled courtyards and sea views tumbling down the hillside.",
      task: Task(
          type: "mascot",
          label: "A fennec is hiding in one of these alleys — find it and photograph it"),
      lat: 36.7853,
      lng: 3.0608),
  Location(
      id: "martyrs",
      name: "Maqam Echahid",
      region: "Algiers & the Casbah",
      category: "Monument",
      distanceKm: 5,
      blurb:
          "Three palm-frond concrete shells rising over the bay, Algiers' memorial to independence.",
      task: Task(type: "video", label: "Film a slow pan across the three palm shells"),
      lat: 36.7527,
      lng: 3.0665),
  Location(
      id: "sidimcid",
      name: "Sidi M'Cid Bridge",
      region: "Constantine",
      category: "Bridge",
      distanceKm: 14,
      blurb:
          "A suspension bridge slung 175m over the Rhumel gorge, the signature view of the City of Bridges.",
      task: Task(type: "video", label: "Capture a short clip crossing the bridge"),
      lat: 36.3705,
      lng: 6.6147),
  Location(
      id: "ahmedbey",
      name: "Ahmed Bey Palace",
      region: "Constantine",
      category: "Palace",
      distanceKm: 15,
      blurb:
          "Marble courtyards and painted ceilings inside the last Ottoman bey's residence.",
      task: Task(type: "scan", label: "Scan the painted ceiling medallion"),
      lat: 36.3646,
      lng: 6.6088),
  Location(
      id: "djemila",
      name: "Djemila",
      region: "Djemila & Timgad",
      category: "Roman ruins",
      distanceKm: 52,
      blurb:
          "A Roman market town scattered across a mountain ridge, its forum still catching the evening light.",
      task: Task(type: "scan", label: "Scan the forum's inscription stone"),
      lat: 36.3214,
      lng: 5.7358),
  Location(
      id: "timgad",
      name: "Timgad",
      region: "Djemila & Timgad",
      category: "Roman ruins",
      distanceKm: 61,
      blurb:
          "A grid-planned Roman colony known as the Pompeii of Africa, arch and colonnade intact.",
      task: Task(type: "video", label: "Film Trajan's Arch from below"),
      lat: 35.4842,
      lng: 6.4675),
  Location(
      id: "tassili",
      name: "Tassili n'Ajjer",
      region: "Tassili n'Ajjer / Sahara",
      category: "Desert plateau",
      distanceKm: 38,
      blurb:
          "Sandstone spires and 8,000-year-old rock art scattered across a Saharan plateau.",
      task: Task(
          type: "mascot",
          label: "A fennec is hiding on the plateau — find it and photograph it"),
      lat: 24.5544,
      lng: 9.4842),
  Location(
      id: "gouraya",
      name: "Yemma Gouraya",
      region: "Kabylie mountains & coast",
      category: "Coastal peak",
      distanceKm: 29,
      blurb:
          "A clifftop shrine over the Bay of Bejaia, with the Kabylie coastline unrolling below.",
      task: Task(type: "video", label: "Film the coastline from the shrine"),
      lat: 36.7628,
      lng: 5.0921)
];

// The folder used to be seeded with four hard-coded example artifacts. They
// rendered as placeholder cubes indistinguishable from a real capture, and
// outlived every genuine one because those were only ever held in bloc state.
// The folder is now built from the user's own artifacts alone — see
// ArtifactRepository.
