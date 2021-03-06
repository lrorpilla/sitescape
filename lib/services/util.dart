import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fuzzy/fuzzy.dart';
import 'package:intl/intl.dart';
import 'package:image_editor/image_editor.dart';
import 'package:path/path.dart' as ph;
import 'package:aes_crypt/aes_crypt.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'package:weather/weather_library.dart';

import 'package:sitescape/main.dart';
import 'package:sitescape/services/classes.dart';

/* Used to await an image and pre-cache it so it loads without blinking in.
   Used for the splash screen, where image takes time to load and thus
   looks ugly without this.
  
   url -> String: Path to image to pre-cache
*/
Future<Uint8List> loadImage(String url) {
  ImageStreamListener listener;

  final Completer<Uint8List> completer = Completer<Uint8List>();
  final ImageStream imageStream =
      AssetImage(url).resolve(ImageConfiguration.empty);

  listener = ImageStreamListener(
    (ImageInfo imageInfo, bool synchronousCall) {
      imageInfo.image
          .toByteData(format: ui.ImageByteFormat.png)
          .then((ByteData byteData) {
        imageStream.removeListener(listener);
        completer.complete(byteData.buffer.asUint8List());
      });
    },
    onError: (dynamic exception, StackTrace stackTrace) {
      imageStream.removeListener(listener);
      completer.completeError(exception);
    },
  );

  imageStream.addListener(listener);

  return completer.future;
}

/* Generate a cryptographic hash from a file using SHA-256, useful for
   filenames to prevent sequential naming collisions. */
String generateFileHash(File file) {
  // Read the bytes from the file and encode UTF-8.
  var bytes = file.readAsBytesSync().toString();
  var encoded = utf8.encode(bytes);

  // SHA256 - which outputs in base16.
  var hash = sha256.convert(encoded);

  // Encoding the raw bytes from SHA256 in base64 should give us more entropy
  // when truncating the filename to 8 characters.
  var base64Str = base64UrlEncode(hash.bytes).replaceAll("_", ",");

  return base64Str;
}

String generateStringHash(String text) {
  var encoded = utf8.encode(text);

  // SHA256 - which outputs in base16.
  var hash = sha256.convert(encoded);

  // Encoding the raw bytes from SHA256 in base64 should give us more entropy
  // when truncating the filename to 8 characters.
  var base64Str = base64UrlEncode(hash.bytes);
  return base64Str;
}

/* Used to check if an internet connection is available to prevent futile
   connection attempts in app behaviour. */
Future<bool> isConnectionAvailable() async {
  try {
    final result = await InternetAddress.lookup('tfsitescape.firebaseio.com');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      return true;
    }
  } on SocketException catch (_) {
    return false;
  }
  return false;
}

/* Used to check if location services is available to prevent futile
   location request attempts in app behaviour. */
Future<bool> isLocationAvailable() async {
  bool enabled = await Geolocator().isLocationServiceEnabled();
  return enabled;
}

/* Refreshes site data and saves the new data in the local cache for offline
   use. Offline callback is called if there is no internet available to
   trigger a message from the current context. 
   
   {offlineCallback -> void}: Calls when internet is unavailable
*/
Future refreshSites({offlineCallback}) async {
  gSites = [];

  String siteCacheDir = gExtDir.path + "/.sites";
  File(siteCacheDir).createSync();

  bool isOnline = await isConnectionAvailable();
  if (!isOnline) {
    offlineCallback();
    loadLocalSites();
    return;
  }

  final StorageReference sitesRef =
      FirebaseStorage.instance.ref().child("tfcloud").child("sites.json");

  String url = await sitesRef.getDownloadURL();

  var siteBytes = await http.get(url);
  String sitesJson = siteBytes.body;
  print(sitesJson);

  gSites = jsonToSites(sitesJson);
  gSites.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  String cacheContents = json.encode(sitesJson);
  print(cacheContents);

  var crypt = AesCrypt('KinomotoSakura');
  crypt.setOverwriteMode(AesCryptOwMode.on);
  crypt.encryptTextToFileSync(cacheContents, siteCacheDir);

  return;
}

Future<Site> getLastSiteAccessed() async {
  String lastSiteCacheDir = gExtDir.path + "/.lastaccessed";
  File lastSiteCache = File(lastSiteCacheDir);

  if (lastSiteCache.existsSync()) {
    for (int i = 0; i < gSites.length; i++) {
      if (lastSiteCache.readAsStringSync() == gSites[i].code) {
        return gSites[i];
      }
    }
  }
  return null;
}

void setLastSiteAccessed(Site site) {
  String lastSiteCacheDir = gExtDir.path + "/.lastaccessed";
  File lastSiteCache = File(lastSiteCacheDir);

  lastSiteCache.createSync();
  lastSiteCache.writeAsStringSync(site.code);
}

void freeUpSpace() {
  List<FileSystemEntity> files = gExtDir.listSync(recursive: true);

  for (FileSystemEntity i in files) {
    if (ph.extension(i.path) == ".jpg" &&
        (!ph.basenameWithoutExtension(i.path).endsWith("_L"))) {
      print("FILE DELETE: " + i.path);
      i.deleteSync();
    }

    if (ph.extension(i.path) == ".notrequired") {
      print("FILE DELETE: " + i.path);
      i.deleteSync();
    }
  }
}

/* If the cache exists, load it. Used on startup so that site data is
   available on startup. */
Future loadLocalSites() async {
  gSites = [];

  String siteCacheDir = gExtDir.path + "/.sites";
  String contents;

  try {
    var crypt = AesCrypt('KinomotoSakura');
    contents = json.decode(crypt.decryptTextFromFileSync(siteCacheDir));
  } catch (e) {}

  if (contents != null) {
    print("Site cache exists: " + siteCacheDir);

    gSites = jsonToSites(contents);
    gSites.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } else {
    print("Site cache not found.");
    gSites = [];
  }
}

/* Returns a pleasant greeting appropriate to current device time. */
String getTimeFlavour() {
  TimeOfDay now = TimeOfDay.now();
  if (now.hour >= 5 && now.hour < 12) {
    return "Good morning";
  } else if (now.hour >= 12 && now.hour <= 17) {
    return "Good afternoon";
  } else {
    return "Good evening";
  }
}

ImageProvider getWeatherImage(Weather weather) {
  switch (weather.weatherIcon) {
    case "01d":
    case "01n":
      return AssetImage("images/home/weather_clear.png");
    case "02d":
    case "02n":
    case "03d":
    case "03n":
    case "04d":
    case "04n":
      return AssetImage("images/home/weather_cloudy.png");
    case "09d":
    case "09n":
    case "10d":
    case "10n":
      return AssetImage("images/home/weather_rainy.png");
    case "11d":
    case "11n":
      return AssetImage("images/home/weather_stormy.png");
    case "13d":
    case "13n":
      return AssetImage("images/home/weather_snowy.png");
      break;
    case "50d":
    case "50n":
      return AssetImage("images/home/weather_foggy.png");
      break;
    default:
      return AssetImage("images/home/weather_clear.png");
      break;
  }
}

/* Returns weather from OpenWeather API. */
Future<Weather> getWeather() async {
  if (gUserLatitude == null || gUserLongitude == null) {
    // Get current user's GPS coordinates.
    Position position = await Geolocator()
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    gUserLatitude = position.latitude;
    gUserLongitude = position.longitude;
  }

  WeatherStation weatherStation =
      new WeatherStation("d61e123d47c998fb20c54a8cc5bc300b");

  Weather weather =
      await weatherStation.currentWeather(gUserLatitude, gUserLongitude);
  return weather;
}

/* Iterate on all Sites and return the ones with closest distance.
   Returns [List<Site>, List<double>], closest site and distance. */
Future<List<dynamic>> getThreeClosestSites() async {
  if (gUserLatitude == null || gUserLongitude == null) {
    // Get current user's GPS coordinates.
    Position position = await Geolocator()
        .getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    gUserLatitude = position.latitude;
    gUserLongitude = position.longitude;
  }

  // List of closest Sites and distances to return
  List<Site> closestSites = [];
  List<double> closestDistances = [];
  // Necessary as we'll be manipulating and removing from this list
  List<Site> allSites = []..addAll(gSites);
  List<double> allDistances = [];

  // Get all distances from every site
  for (Site i in allSites) {
    allDistances.add(
      await Geolocator().distanceBetween(
          i.latitude, i.longitude, gUserLatitude, gUserLongitude),
    );
  }

  // Perform three times as we are getting three of the closest Sites
  for (int i = 0; i < 3; i++) {
    double minimum = -1;
    // Get the minimum distance among all Sites
    for (var i = 0; i < allDistances.length; i++) {
      if (minimum == -1 || minimum > allDistances[i]) {
        minimum = allDistances[i];
      }
    }

    // Get the site index of the minimum
    int indexMin = allDistances.indexOf(minimum);

    // Add these Sites/distances of the min's index to the appropriate lists
    closestSites.add(allSites[indexMin]);
    closestDistances.add(allDistances[indexMin]);

    // Remove these Sites from the list to check in the next iteration
    allSites.removeAt(indexMin);
    allDistances.removeAt(indexMin);
  }

  return [closestSites, closestDistances];
}

/* Return the appropriate unit of measurement as a suffix to a given
   distance in meters. 

   distance -> double: Distance in meters 
*/
String getDistanceText(double distance) {
  // If meters is greater than 1000, use km instead.
  if (distance >= 1000) {
    int m = distance ~/ 1000;
    return m.toString() + "km";
  } else {
    int m = distance.round();
    return m.toString() + "m";
  }
}

/* Uses Fuzzy string searching to filter Sites in search properly. Limit
   is used to limit the search results for performance.
   
   searchTerm -> String: String to use for a filter
   limit -> int: The max number of Sites to return */
List<Site> filterSitesByNameOrCode(String searchTerm, int limit) {
  // If the search term is blank, return the Sites in alphabetical order
  // as already sorted
  if (searchTerm == "") {
    // return [];
    // Safety for when limit exceeds the site length
    if (limit > gSites.length) {
      limit = gSites.length;
    }

    return gSites.sublist(0, limit);
  }

  // Useful so we can iterate on these and get their site indexes
  List<String> names = [];
  List<String> codes = [];
  // To fairly discern between codes and names in the search
  List<String> namesAndCodes = [];

  for (int i = 0; i < gSites.length; i++) {
    names.add(gSites[i].name);
    codes.add(gSites[i].code);
    namesAndCodes.add(gSites[i].name);
    namesAndCodes.add(gSites[i].code);
  }

  // Perform a Fuzzy string search with the term on all names/codes
  final fuzzy = Fuzzy(
    namesAndCodes,
    options: FuzzyOptions(
      threshold: 0.2,
      shouldSort: true,
      findAllMatches: false,
    ),
  );
  final results = fuzzy.search(searchTerm);

  // Safety for when limit exceeds the results length
  if (results.length < limit) {
    limit = results.length;
  }

  List<Site> bestResults = [];
  for (int i = 0; i < limit; i++) {
    // Get the index of a name match
    int addIndex = names.indexOf(results[i].item);
    // If it's not a name match, it must be a code match
    if (addIndex == -1) {
      addIndex = codes.indexOf(results[i].item);
    }

    // If an index match is found, add it
    if (addIndex != -1 && !bestResults.contains(gSites[addIndex])) {
      bestResults.add(gSites[addIndex]);
    }
  }

  return bestResults;
}

/* Draw a watermark on top of an image and return the manipulated file
   with the appropriate timestamp.

   pathToImage -> String: The path to the file to manipulate. */
Future<File> bakeTimestamp(File file, {bool bearings = false}) async {
  // Get current time for timestamp to bake
  DateTime now = DateTime.now();
  String timeStamp = DateFormat('yyyy-MM-dd kk:mm:ss').format(now);

  // Set up the text option to use to edit the image
  final textOption = AddTextOption();
  // For code redundancy as this is called four times
  void addWatermark(
    double x,
    double y,
    Color color,
    String text,
  ) {
    textOption.addText(
      EditorText(
        offset: Offset(x, y),
        text: text,
        fontSizePx: 36,
        textColor: color,
      ),
    );
  }

  // For compass bearings
  double compassDouble = await FlutterCompass.events.first;
  int compassValue = compassDouble.floor();
  int compassRelative = compassValue.floor() % 90;

  String trueBearing = compassValue.toString() + "°T";
  String relativeBearing;

  if (0 <= compassValue && compassValue < 90) {
    relativeBearing = "N " + compassRelative.toString() + "°E";
  } else if (90 <= compassValue && compassValue < 180) {
    relativeBearing = "S " + compassRelative.toString() + "°E";
  } else if (180 <= compassValue && compassValue < 270) {
    relativeBearing = "S " + compassRelative.toString() + "°W";
  } else {
    relativeBearing = "N " + compassRelative.toString() + "°W";
  }

  String compass = trueBearing + ", " + relativeBearing;

  // For black border
  addWatermark(9, 11, Colors.black, timeStamp);
  addWatermark(11, 9, Colors.black, timeStamp);
  addWatermark(11, 11, Colors.black, timeStamp);
  addWatermark(9, 9, Colors.black, timeStamp);
  // For white on top of the black border
  addWatermark(10, 10, Colors.white, timeStamp);

  if (bearings == true) {
    // For black border
    addWatermark(9, 59, Colors.black, compass);
    addWatermark(11, 57, Colors.black, compass);
    addWatermark(11, 59, Colors.black, compass);
    addWatermark(9, 57, Colors.black, compass);
    // For white on top of the black border
    addWatermark(10, 58, Colors.white, compass);
  }

  final editorOption = ImageEditorOption();
  editorOption.addOption(textOption);

  // Perform the operation
  return ImageEditor.editFileImageAndGetFile(
    file: file,
    imageEditorOption: editorOption,
  );
}

Future launchURL() async {
  const url =
      'https://drive.google.com/file/d/1KMVp7aJN_fHHkdnKMZ94yiSEjWcvzp3v/view';
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
