import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_blue/flutter_blue.dart';
import 'package:location/location.dart';
import 'package:http/http.dart' as http;

final String databaseURL =
    "YOUR_URL_HERE";

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Beacon Scanner',
      home: new BeaconsView(),
      theme: ThemeData(
        primaryColor: Colors.blue[800],
        accentColor: Colors.blue,
      ),
    );
  }
}

/**
 * This stateful widget contains the list of beacons found in range.
 */
class BeaconsView extends StatefulWidget {
  @override
  BeaconsViewState createState() => new BeaconsViewState();
}

/**
 * State of the BeaconsView widget
 */
class BeaconsViewState extends State<BeaconsView> {
  // Map which holds all visible beacons.
  // For now our beacons have an ID and a link. The third parameter is
  // a boolean indicating if data from that beacon exists on the server
  var beacons = {
    // "uid1": {
    //   "payload": "http://www.google.com",
    //   "lastUploaded": null,
    //   "uploaded": false,
    //   "location": null
    // },
    // "uid2": {
    //   "payload": "http://www.duckduckgo.com",
    //   "lastUploaded": null,
    //   "uploaded": false,
    //   "location": null
    // }
  };

  // Bluetooth controller instance
  FlutterBlue flutterBlue = FlutterBlue.instance;
  StreamSubscription scanSubscription;

  // Location instance
  var location = new Location();

  // Flag which marks a refresh operation
  bool refreshing = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    setState(() {
      refreshing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Center(
            child: Text("BLE Beacons in range"),
          ),
          actions: <Widget>[
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: refreshing ? null : _startScanBLE,
            )
          ],
        ),
        body: Center(
          child: BeaconsList(beacons, _uploadData),
        ),
        // Just a Floating Action button to upload everything
        bottomNavigationBar: beacons.keys.toList().length > 0
            ? Padding(
                padding: EdgeInsets.all(20.0),
                child: FloatingActionButton(
                  tooltip: "Upload beacon data",
                  elevation: 2.0,
                  onPressed: _uploadAllData,
                  mini: false,
                  child: Icon(Icons.cloud_upload),
                ),
              )
            : null);
  }

  _getCurrentLocation() async {
    try {
      var currentLocation = await location.getLocation;
      setState(() {
        beacons.forEach((key, val) {
          beacons[key]["location"] = currentLocation;
        });
      });
    } on Exception {
      print("Exception!");
    }
  }

  /**
   * Starts a scan of the nearby BLE devices and populates the device list
   */
  _startScanBLE() {
    setState(() {
      refreshing = true;
      beacons = {};
    });

    scanSubscription = flutterBlue
        .scan(timeout: const Duration(seconds: 5))
        .listen((ScanResult result) {
      // print("Scan completed.");
      result.advertisementData.serviceData.forEach((key, val) {
        String uid = val.sublist(1, 3).join(" ");
        print("hello");
        print(uid);
        String payload = String.fromCharCodes(val.sublist(3));

        var beacon = {
          "payload": payload,
          "lastUploaded": null,
          "uploaded": false
        };

        if (!beacons.containsKey(uid)) {
          print(beacon);
          setState(() {
            beacons[uid] = beacon;
          });
        }
      });
    }, onDone: () {
      scanSubscription?.cancel();
      setState(() {
        refreshing = false;
      });
      // Also update all beacons with current location
      _getCurrentLocation();
    });
  }

  _uploadAllData() {
    beacons.keys.forEach((uid){
      _uploadData(uid);
    });
  }

  // Upload the beacon from the list with the index to the cloud
  _uploadData(String uid) {
    setState(() {
      beacons[uid]["uploaded"] = true;
      beacons[uid]["lastUploaded"] = DateTime.now();
    });
    var tempBeacon = new Map.from(beacons[uid]);
    tempBeacon["lastUploaded"] = tempBeacon["lastUploaded"]?.toString();

    String json = jsonEncode(tempBeacon);

    http.patch(databaseURL, body: '{"${uid}": ${json}}').then(
        (response) {
      print("Response status: ${response.statusCode}");
      print("Response body: ${response.body}");
    });
  }
}

/**
 * Stateless widget containing the list of beacons. This is re-rendered
 * whenever the state in the BeaconsView changed.
 */
class BeaconsList extends StatelessWidget {
  Map beacons; // List of discovered beacons
  Function uploadCallback;

  BeaconsList(Map beacons, Function uploadCallback) {
    this.beacons = beacons;
    this.uploadCallback = uploadCallback;
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemBuilder: (BuildContext context, int i) {
        if (i >= beacons.keys.toList().length) {
          return null;
        }

        String uid = beacons.keys.toList()[i];
        var location = beacons[uid]["location"];
        // Nice little Card
        return new Card(
          elevation: 2.0,
          margin: EdgeInsets.fromLTRB(10.0, 5.0, 10.0, 5.0),
          child: ListTile(
            contentPadding: EdgeInsets.all(10.0),
            trailing: IconButton(
              icon: Icon(Icons.cloud_upload),
              color: beacons[uid]["uploaded"] ? Colors.blue : null,
              onPressed: () => this.uploadCallback(uid),
            ),
            title: Text(
              uid,
              style: TextStyle(fontSize: 20.0),
            ),
            // Beacon-related data is layed out on one column (multiple rows)
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Divider(),
                DetailRow("Payload: ", beacons[uid]["payload"]),
                DetailRow(
                    "Last Uploaded: ",
                    beacons[uid]["uploaded"]
                        ? DateFormat
                            .yMMMd()
                            .add_jm()
                            .format(beacons[uid]["lastUploaded"])
                        : "N/A"),
                DetailRow(
                    "Location: ",
                    location == null
                        ? null
                        : "Lon: " +
                            location["longitude"].toStringAsFixed(2) +
                            "  Lat: " +
                            location["latitude"].toStringAsFixed(2) +
                            "  Alt: " +
                            location["altitude"].toStringAsFixed(0) +
                            "m")
              ],
            ),
          ),
        );
      },
    );
  }
}

/**
 * Each row of data related to the beacon will have this format
 */
class DetailRow extends StatelessWidget {
  String heading;
  String detail;

  DetailRow(String heading, String detail) {
    this.heading = heading;
    this.detail = detail;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
        text: TextSpan(
            style: new TextStyle(
              fontSize: 14.0,
              color: Colors.black54,
            ),
            children: <TextSpan>[
          TextSpan(
              text: this.heading,
              style: new TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: this.detail),
        ]));
  }
}
