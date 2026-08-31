class Device {
  final String name;
  final String address;
  final String bleId;

  Device({required this.name, required this.address, required this.bleId});

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'bleId': bleId,
  };

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      name: json['name'] as String,
      address: json['address'] as String,
      bleId: json['bleId'] as String,
    );
  }
}
