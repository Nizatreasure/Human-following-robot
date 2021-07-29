import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:geolocator/geolocator.dart';
import 'package:fluttertoast/fluttertoast.dart';

void main() {
  runApp(MaterialApp(home: HomePage()));
}

class HomePage extends StatefulWidget {
  const HomePage({Key key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  FlutterBluetoothSerial _bluetooth = FlutterBluetoothSerial.instance;
  BluetoothConnection connection;
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  List<BluetoothDevice> _devicesList = [];
  bool isDisconnecting = false;
  bool _connected = false;
  BluetoothDevice _device;
  bool _isButtonUnavailable = false;
  AnimationController _controller;
  Animation<double> _animation;
  bool get isConnected => connection != null && connection.isConnected;
  Position position;
  StreamSubscription _positionStream;
  bool useFixedLocation = false;
  String lat = '', long = '';
  TextEditingController latEditingController;
  TextEditingController longEditingController;
  bool followMe = false;
  bool enableRobot = false;

  @override
  void initState() {
    if (isConnected) {
      setState(() {
        _connected = true;
      });
    }
    _controller =
        AnimationController(vsync: this, duration: Duration(seconds: 1));
    _animation = Tween<double>(begin: 0, end: 1).animate(_controller);

    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          _isButtonUnavailable = true;
        }
      });
    });
    _getLocation();
    enableBluetooth();

    FlutterBluetoothSerial.instance.onStateChanged().listen((state) {
      setState(() {
        _bluetoothState = state;
        getPairedDevices();
      });
    });
    super.initState();
  }

  Future<void> enableBluetooth() async {
    _bluetoothState = await FlutterBluetoothSerial.instance.state;

    if (_bluetoothState == BluetoothState.STATE_OFF) {
      await FlutterBluetoothSerial.instance.requestEnable();
      setState(() {
        _isButtonUnavailable = false;
      });
      await getPairedDevices();
      return true;
    } else {
      await getPairedDevices();
    }
    return false;
  }

  Future<void> getPairedDevices() async {
    List<BluetoothDevice> devices = [];

    try {
      devices = await _bluetooth.getBondedDevices();
    } on PlatformException {
      print("Error");
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _devicesList = devices;
    });
  }

  void _connect() async {
    setState(() {
      _isButtonUnavailable = true;
    });
    if (_device == null) {
      Fluttertoast.showToast(msg: 'No device selected');
      setState(() {
        _isButtonUnavailable = false;
      });
    } else {
      if (!isConnected) {
        await BluetoothConnection.toAddress(_device.address)
            .then((_connection) {
          print('Connected to the device');
          connection = _connection;

          Fluttertoast.showToast(msg: 'Device connected');

          setState(() {
            _connected = true;
            isDisconnecting = false;
          });

          connection.input.listen(null).onDone(() {
            if (isDisconnecting) {
              print('Disconnecting locally!');
            } else {
              print('Disconnected remotely!');
            }
            if (this.mounted) {
              setState(() {});
            }
          });
        }).catchError((error) {
          print('Cannot connect, exception occurred');
          print(error);
        });

        setState(() => _isButtonUnavailable = false);
      }
    }
  }

  void _disconnect() async {
    setState(() {
      _isButtonUnavailable = true;
    });
    await connection.close();

    Fluttertoast.showToast(msg: 'Device disconnected');

    if (!connection.isConnected) {
      setState(() {
        _connected = false;
        _isButtonUnavailable = false;
      });
    }
  }

  List<DropdownMenuItem<BluetoothDevice>> _getDeviceItems() {
    List<DropdownMenuItem<BluetoothDevice>> items = [];
    if (_devicesList.isEmpty) {
      items.add(DropdownMenuItem(
        child: Text('NONE'),
      ));
    } else {
      _devicesList.forEach((device) {
        items.add(DropdownMenuItem(
          child: Text(device.name),
          value: device,
        ));
      });
    }
    return items;
  }

  void _followUser() async {
    if (connection != null && connection.isConnected && position != null) {
      connection.output.add(utf8.encode("F-" +
          position.latitude.toString() +
          "," +
          position.longitude.toString() +
          ":" +
          "\r\n"));
      await connection.output.allSent;
    } else
      Fluttertoast.showToast(msg: "Device not connected");
  }

  void _goToPosition(String lat, String long) async {
    if (connection != null && connection.isConnected) {
      setState(() {});
      connection.output
          .add(utf8.encode("G-" + lat + "," + long + ":" + "\r\n"));
      await connection.output.allSent;
    } else
      Fluttertoast.showToast(msg: 'Device not connected');
  }

  void toggleSwitch(int num) async {
    if (connection != null && connection.isConnected) {
      connection.output
          .add(utf8.encode("T-" + num.toString() + "," + "0:" + "\r\n"));
      await connection.output.allSent;
      Fluttertoast.showToast(
          msg: num == 0 ? 'Robot disabled' : 'Robot enabled');
      setState(() {
        enableRobot = num == 1 ? true : false;
      });
    } else
      Fluttertoast.showToast(msg: 'Device not connected');
  }

  void _getLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      showLocationWarning('Please turn on your location to continue', 2);
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        showLocationWarning(
            'Please grant this app access to your location to continue', 1);
      }
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
    }

    _positionStream = Geolocator.getPositionStream(
            desiredAccuracy: LocationAccuracy.high,
            intervalDuration: Duration(seconds: 10))
        .listen((Position userPosition) {
      if (userPosition != null) {
        position = userPosition;
        if (followMe && _connected && enableRobot) {
          _followUser();
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _positionStream.cancel();
    latEditingController.dispose();
    longEditingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.grey[500],
      appBar: AppBar(
        title: Text("Human Following Robot"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          TextButton.icon(
              onPressed: () async {
                _controller.forward()..whenComplete(() => _controller.reset());

                await getPairedDevices();
              },
              icon: RotationTransition(
                  turns: _animation, child: Icon(Icons.refresh)),
              label: Text('Refresh'))
        ],
      ),
      body: LayoutBuilder(builder: (context, constraint) {
        return SingleChildScrollView(
          child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraint.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text('Enable Bluetooth'),
                      value: _bluetoothState.isEnabled,
                      controlAffinity: ListTileControlAffinity.trailing,
                      onChanged: (bool value) {
                        future() async {
                          if (value) {
                            await FlutterBluetoothSerial.instance
                                .requestEnable();
                          } else {
                            await FlutterBluetoothSerial.instance
                                .requestDisable();
                          }

                          await getPairedDevices();
                          _isButtonUnavailable = false;

                          if (_connected) {
                            _disconnect();
                          }
                        }

                        future().then((_) {
                          setState(() {});
                        });
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Device:',
                            style: TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold),
                          ),
                          SizedBox(width: 10),
                          DropdownButton(
                            items: _getDeviceItems(),
                            iconEnabledColor: Colors.black,
                            onChanged: (value) {
                              setState(() => _device = value);
                            },
                            value: _devicesList.isNotEmpty || _device != null
                                ? _device
                                : null,
                            hint: Text('Select a device'),
                          ),
                          SizedBox(width: 20),
                          ElevatedButton(
                            onPressed: _isButtonUnavailable
                                ? null
                                : _connected
                                    ? _disconnect
                                    : _connect,
                            child: Text(_connected ? 'Disconnect' : 'Connect'),
                          )
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.all(30),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SwitchListTile(
                              title: Text('Enable Robot'),
                              value: enableRobot,
                              controlAffinity: ListTileControlAffinity.trailing,
                              onChanged: (bool value) {
                                followMe = false;
                                if (value)
                                  toggleSwitch(1);
                                else
                                  toggleSwitch(0);
                              },
                            ),
                            SwitchListTile(
                              title: Text('Use Fixed Location?'),
                              value: useFixedLocation,
                              controlAffinity: ListTileControlAffinity.trailing,
                              onChanged: (bool value) {
                                setState(() {
                                  useFixedLocation = value;
                                });
                              },
                            ),
                            SizedBox(height: 50),
                            buttons(() {
                              followMe = true;
                              _followUser();
                            }, 'Follow Me', Colors.white, Colors.green,
                                !useFixedLocation),
                            SizedBox(height: 20),
                            buttons(
                              () {
                                followMe = false;
                                enterDirection();
                              },
                              'Go to location',
                              Colors.white,
                              Colors.blue,
                              useFixedLocation,
                            ),
                            if (useFixedLocation == true &&
                                lat != null &&
                                lat.isNotEmpty &&
                                long != null &&
                                long.isNotEmpty)
                              Container(
                                height: 100,
                                margin: EdgeInsets.only(top: 30),
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 15),
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Column(
                                  children: [
                                    Text("Drive To Location",
                                        style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold)),
                                    SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Text('Latitude:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16)),
                                        SizedBox(width: 10),
                                        Text(lat)
                                      ],
                                    ),
                                    SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Text('Longitude:',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 16)),
                                        SizedBox(width: 10),
                                        Text(long)
                                      ],
                                    )
                                  ],
                                ),
                              )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        );
      }),
    );
  }

  Widget buttons(Function function, String text, Color textColor, Color bColor,
      bool enabled) {
    return InkWell(
      onTap: !enableRobot
          ? () {
              Fluttertoast.showToast(msg: "Please enable the robot");
            }
          : !enabled
              ? () {
                  if (useFixedLocation)
                    Fluttertoast.showToast(
                        msg: "Please turn off 'Use Fixed Location'");
                  else
                    Fluttertoast.showToast(
                        msg: "Please enable 'Use Fixed Location'");
                }
              : () {
                  function();
                },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        width: double.infinity,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: enabled && enableRobot ? bColor : bColor.withOpacity(0.3)),
        alignment: Alignment.center,
        child: Text(
          text,
          style: TextStyle(
              color: enabled && enableRobot
                  ? textColor
                  : textColor.withOpacity(0.4),
              fontWeight: FontWeight.bold,
              fontSize: 17),
        ),
      ),
    );
  }

  Future enterDirection() {
    latEditingController = TextEditingController(text: lat);
    longEditingController = TextEditingController(text: long);
    return showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) {
          return AlertDialog(
            backgroundColor: Colors.grey[500],
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Input location details below',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
                SizedBox(
                  height: 12,
                ),
                SizedBox(
                  height: 45,
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        child: Text(
                          'Latitude:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.numberWithOptions(),
                          inputFormatters: [],
                          controller: latEditingController,
                          decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide:
                                      BorderSide(color: Colors.transparent)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide:
                                      BorderSide(color: Colors.transparent)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                      color: Colors.grey[600], width: 2)),
                              filled: true,
                              fillColor: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
                SizedBox(
                  height: 45,
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        child: Text(
                          'Longitude:',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.numberWithOptions(),
                          controller: longEditingController,
                          decoration: InputDecoration(
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide:
                                      BorderSide(color: Colors.transparent)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide:
                                      BorderSide(color: Colors.transparent)),
                              focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                  borderSide: BorderSide(
                                      color: Colors.grey[600], width: 2)),
                              filled: true,
                              fillColor: Colors.grey[400]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text("Cancel",
                      style: TextStyle(color: Colors.red, fontSize: 16))),
              TextButton(
                  onPressed: () {
                    String hLat = latEditingController.text;
                    String hLong = longEditingController.text;
                    if (hLat != null &&
                        hLat.isNotEmpty &&
                        hLong != null &&
                        hLong.isNotEmpty) {
                      if (connection == null || !connection.isConnected)
                        Fluttertoast.showToast(msg: 'Device not connected');
                      else {
                        lat = hLat;
                        long = hLong;
                        _goToPosition(lat, long);
                        Navigator.pop(context);
                      }
                    } else
                      Fluttertoast.showToast(msg: 'Fields cannot be empty');
                  },
                  style: ButtonStyle(
                      backgroundColor:
                          MaterialStateProperty.all<Color>(Colors.blue)),
                  child: Text("Done",
                      style: TextStyle(color: Colors.white, fontSize: 17))),
            ],
          );
        });
  }

  showLocationWarning(String text, int type) {
    return showDialog(
        context: context,
        builder: (_) {
          return AlertDialog(
            backgroundColor: Colors.grey[500],
            content: Text(text),
            actions: [
              TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text("Cancel",
                      style: TextStyle(color: Colors.red, fontSize: 16))),
              TextButton(
                  onPressed: () async {
                    _getLocation();
                    if (type == 1)
                      await Geolocator.openAppSettings();
                    else
                      await Geolocator.openLocationSettings();
                    Navigator.pop(context);
                  },
                  style: ButtonStyle(
                      backgroundColor:
                          MaterialStateProperty.all<Color>(Colors.blue)),
                  child: Text("Open settings",
                      style: TextStyle(color: Colors.white, fontSize: 17))),
            ],
          );
        });
  }
}
