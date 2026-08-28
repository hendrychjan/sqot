class InfluxSettings {
  String url;
  String org;
  String bucket;
  String token;

  InfluxSettings({
    required this.url,
    required this.org,
    required this.bucket,
    required this.token,
  });
}
