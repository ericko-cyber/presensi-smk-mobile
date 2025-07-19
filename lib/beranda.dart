import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'akun.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
  final Map<String, dynamic> siswaData;
  const HomePage({Key? key, required this.siswaData}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  final tanggal = DateFormat('yyyy-MM-dd').format(DateTime.now());
  String tanggalHariIni = DateFormat(
    'EEEE, dd MMMM',
    'id_ID',
  ).format(DateTime.now());
  Position? _currentPosition;
  bool _isLoading = true;
  late int siswaId;
  List<dynamic> _absensiList = [];

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  int _getJumlah(String status) {
    return _absensiList.where((item) => item['keterangan'] == status).length;
  }

  final LatLng sekolahLocation = LatLng(-8.153731800406556, 113.72477426362066);
  late String jamSekarang;
  late Timer _timer;
  late Timer _absensiTimer;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    jamSekarang = DateFormat('HH:mm').format(DateTime.now());
    siswaId = widget.siswaData['id_siswa'];

    _determinePosition();
    fetchAbsensi();

    // Start animations
    _fadeController.forward();
    _slideController.forward();

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          jamSekarang = DateFormat('HH:mm').format(DateTime.now());
        });
      }
    });

    _absensiTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      fetchAbsensi();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _timer.cancel();
    _absensiTimer.cancel();
    super.dispose();
  }

  bool isWaktuPresensiMasuk() {
    final now = DateTime.now();
    final jamMasukMulai = TimeOfDay(hour: 6, minute: 30);
    final jamMasukSelesai = TimeOfDay(hour: 8, minute: 0);
    final waktuSekarang = TimeOfDay(hour: now.hour, minute: now.minute);

    return waktuSekarangCompare(waktuSekarang, jamMasukMulai) >= 0 &&
        waktuSekarangCompare(waktuSekarang, jamMasukSelesai) <= 0;
  }

  bool isWaktuPresensiKeluar() {
    final now = DateTime.now();
    final jamKeluarMulai = TimeOfDay(hour: 15, minute: 0);
    final jamKeluarSelesai = TimeOfDay(hour: 17, minute: 0);
    final waktuSekarang = TimeOfDay(hour: now.hour, minute: now.minute);

    return waktuSekarangCompare(waktuSekarang, jamKeluarMulai) >= 0 &&
        waktuSekarangCompare(waktuSekarang, jamKeluarSelesai) <= 0;
  }

  int waktuSekarangCompare(TimeOfDay a, TimeOfDay b) {
    if (a.hour < b.hour || (a.hour == b.hour && a.minute < b.minute)) return -1;
    if (a.hour > b.hour || (a.hour == b.hour && a.minute > b.minute)) return 1;
    return 0;
  }

  bool isWaktuPresensiTelat() {
    final now = DateTime.now();
    final jamTelatMulai = TimeOfDay(hour: 8, minute: 1);
    final jamTelatSelesai = TimeOfDay(hour: 9, minute: 0);
    final waktuSekarang = TimeOfDay(hour: now.hour, minute: now.minute);

    return waktuSekarangCompare(waktuSekarang, jamTelatMulai) >= 0 &&
        waktuSekarangCompare(waktuSekarang, jamTelatSelesai) <= 0;
  }

  Future<void> fetchAbsensi() async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.0.103:8000/api/riwayat-presensi/$siswaId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _absensiList = data['data'];
          });
        }
      }
    } catch (e) {
      print('Error: $e');
    }
  }

  Future<void> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Layanan lokasi tidak aktif', isError: true);
      setState(() => _isLoading = false);
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      _showSnackBar('Izin lokasi ditolak', isError: true);
      setState(() => _isLoading = false);
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
      );

      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });

      bool dekat = await checkJarakPresensi(
        position.latitude,
        position.longitude,
      );

      if (dekat) {
        _showSnackBar('✅ Anda berada di dalam area presensi', isError: false);
      } else {
        _showSnackBar('❌ Anda di luar area presensi', isError: true);
      }
    } catch (e) {
      print('Gagal mendapatkan lokasi: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<bool> checkJarakPresensi(double userLat, double userLng) async {
    double distanceInMeters = Geolocator.distanceBetween(
      userLat,
      userLng,
      sekolahLocation.latitude,
      sekolahLocation.longitude,
    );

    print("🧭 Lokasi pengguna: ($userLat, $userLng)");
    print(
      "🏫 Lokasi sekolah: (${sekolahLocation.latitude}, ${sekolahLocation.longitude})",
    );
    print("📏 Jarak ke sekolah: ${distanceInMeters.toStringAsFixed(2)} meter");

    return distanceInMeters <= 80;
  }

  Future<void> insertPresensiMasuk(int idSiswa, String lokasi) async {
    final now = DateTime.now();
    final tanggal = DateFormat('yyyy-MM-dd').format(now);
    final sudahPresensi = await sudahPresensiMasukHariIni(idSiswa);

    if (sudahPresensi) {
      print('Gagal: sudah melakukan presensi masuk hari ini.');
      return;
    }

    final waktuMasuk = DateFormat('HH:mm:ss').format(now);
    String keterangan = 'hadir';

    if (isWaktuPresensiTelat()) {
      keterangan = 'telat';
    } else if (!isWaktuPresensiMasuk()) {
      print('Gagal: bukan waktu presensi masuk.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.0.103:8000/api/presensi/masuk'),
        body: {
          'id_siswa': idSiswa.toString(),
          'tanggal': tanggal,
          'waktu_masuk': waktuMasuk,
          'lokasi_masuk': lokasi,
          'keterangan': keterangan,
        },
      );

      if (response.statusCode == 200) {
        fetchAbsensi(); // Refresh data
        print('Presensi masuk berhasil dengan keterangan: $keterangan');
      } else {
        print('Gagal presensi masuk. ${response.body}');
      }
    } catch (e) {
      print('Terjadi kesalahan saat presensi masuk: $e');
    }
  }

  Future<void> insertPresensiKeluar(int idSiswa, String lokasi) async {
    final now = DateTime.now();
    final tanggal = DateFormat('yyyy-MM-dd').format(now);
    final sudahMasuk = await sudahPresensiMasukHariIni(idSiswa);

    if (!sudahMasuk) {
      print('Presensi keluar gagal: belum melakukan presensi masuk.');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('http://192.168.0.103:8000/api/presensi/keluar'),
        body: {
          'id_siswa': idSiswa.toString(),
          'tanggal': tanggal,
          'lokasi': lokasi,
        },
      );

      if (response.statusCode == 200) {
        fetchAbsensi(); // Refresh data
        print('Presensi keluar berhasil.');
      } else {
        print('Gagal presensi keluar. ${response.body}');
      }
    } catch (e) {
      print('Terjadi kesalahan saat presensi keluar: $e');
    }
  }

  Future<bool> sudahPresensiMasukHariIni(int idSiswa) async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.0.103:8000/api/presensi/last/$idSiswa'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lastTanggal = DateTime.tryParse(data['tanggal'] ?? '');
        final waktuMasuk = data['waktu_masuk'];

        if (lastTanggal != null &&
            DateFormat('yyyy-MM-dd').format(lastTanggal) ==
                DateFormat('yyyy-MM-dd').format(DateTime.now()) &&
            waktuMasuk != null) {
          return true;
        }
      }
    } catch (e) {
      print('Gagal cek presensi masuk: $e');
    }
    return false;
  }

  Future<bool> sudahPresensiKeluarHariIni(int idSiswa) async {
    try {
      final response = await http.get(
        Uri.parse('http://192.168.0.103:8000/api/presensi/last/$idSiswa'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final lastTanggal = DateTime.tryParse(data['tanggal'] ?? '');
        final waktuKeluar = data['waktu_keluar'];

        if (lastTanggal != null &&
            DateFormat('yyyy-MM-dd').format(lastTanggal) ==
                DateFormat('yyyy-MM-dd').format(DateTime.now()) &&
            waktuKeluar != null) {
          return true;
        }
      }
    } catch (e) {
      print('Gagal cek presensi keluar: $e');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    String namaSiswa = widget.siswaData['nama_siswa'] ?? 'Tidak diketahui';
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: RefreshIndicator(
              onRefresh: fetchAbsensi,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(namaSiswa),
                      const SizedBox(height: 20),
                      _buildProfileCard(namaSiswa),
                      const SizedBox(height: 20),
                      _buildTimeCard(),
                      const SizedBox(height: 20),
                      _buildMapCard(),
                      const SizedBox(height: 20),
                      _buildActionButtons(),
                      const SizedBox(height: 20),
                      _buildAttendanceHistory(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String namaSiswa) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Halo, $namaSiswa! 👋',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tanggalHariIni,
              style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),
          ],
        ),
        GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfilePage(siswaData: widget.siswaData),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.person,
              size: 28,
              color: Color.fromARGB(255, 5, 74, 222),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileCard(String namaSiswa) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF60A5FA),
            Color(0xFF3B82F6),
          ], // Biru muda → Biru utama
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3B82F6).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.school, size: 32, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Siswa',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      namaSiswa,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'Hadir',
                  _getJumlah('hadir').toString(),
                  Icons.check_circle,
                  const Color(0xFF3B82F6), // Biru utama
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Telat',
                  _getJumlah('telat').toString(),
                  Icons.access_time,
                  const Color(0xFFF59E0B), // Kuning
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'Absen',
                  _getJumlah('absen').toString(),
                  Icons.cancel,
                  const Color(0xFFEF4444), // Merah
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Waktu Sekarang',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            jamSekarang,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                'Waktu Indonesia Barat',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMapCard() {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF06923A)),
              )
            : _currentPosition == null
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.location_off,
                      size: 48,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Lokasi tidak ditemukan',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 16),
                    ),
                  ],
                ),
              )
            : FlutterMap(
                options: MapOptions(
                  center: LatLng(
                    _currentPosition!.latitude,
                    _currentPosition!.longitude,
                  ),
                  zoom: 16.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: 'com.example.presensi_smk',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 40.0,
                        height: 40.0,
                        point: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF06923A),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF06923A).withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            'Check In',
            Icons.login,
            const Color(0xFF06923A),
            () => _handleCheckIn(),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildActionButton(
            'Check Out',
            Icons.logout,
            const Color(0xFFEF4444),
            () => _handleCheckOut(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      shadowColor: color.withOpacity(0.3),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color, color.withOpacity(0.8)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleCheckIn() async {
    if (_currentPosition == null) return;

    String lokasi =
        "${_currentPosition!.latitude}, ${_currentPosition!.longitude}";

    // Cek apakah sudah presensi hari ini
    bool sudahPresensi = await sudahPresensiMasukHariIni(
      widget.siswaData['id_siswa'],
    );
    if (sudahPresensi) {
      _showDialog(
        'Sudah Presensi',
        'Anda sudah melakukan presensi masuk hari ini.',
        isError: true,
      );
      return;
    }

    // Validasi waktu presensi
    if (!isWaktuPresensiMasuk() && !isWaktuPresensiTelat()) {
      _showDialog(
        'Di luar waktu presensi',
        'Presensi masuk hanya antara 06:30 - 09:00.',
        isError: true,
      );
      return;
    }

    // Validasi lokasi
    bool bisaPresensi = await checkJarakPresensi(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    if (bisaPresensi) {
      await insertPresensiMasuk(widget.siswaData['id_siswa'], lokasi);
    }

    // Tampilkan pesan dialog berdasarkan status
    _showDialog(
      bisaPresensi ? 'Berhasil! 🎉' : 'Gagal ❌',
      bisaPresensi
          ? (isWaktuPresensiTelat()
                ? 'Presensi berhasil, namun Anda terlambat.'
                : 'Presensi masuk berhasil dilakukan!')
          : 'Anda berada di luar area presensi.',
      isError: !bisaPresensi,
    );
  }

  Future<void> _handleCheckOut() async {
    if (_currentPosition == null) return;

    String lokasi =
        "${_currentPosition!.latitude}, ${_currentPosition!.longitude}";

    if (!isWaktuPresensiKeluar()) {
      _showDialog(
        'Di luar waktu presensi',
        'Presensi keluar hanya antara 10:00 - 17:00.',
        isError: true,
      );
      return;
    }

    bool sudahMasuk = await sudahPresensiMasukHariIni(
      widget.siswaData['id_siswa'],
    );
    if (!sudahMasuk) {
      _showDialog(
        'Belum Presensi Masuk',
        'Anda belum melakukan presensi masuk hari ini.',
        isError: true,
      );
      return;
    }

    bool sudahKeluar = await sudahPresensiKeluarHariIni(
      widget.siswaData['id_siswa'],
    );
    if (sudahKeluar) {
      _showDialog(
        'Sudah Presensi Keluar',
        'Anda sudah melakukan presensi keluar hari ini.',
        isError: true,
      );
      return;
    }

    bool bisaPresensi = await checkJarakPresensi(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
    );

    if (bisaPresensi) {
      await insertPresensiKeluar(widget.siswaData['id_siswa'], lokasi);
    }

    _showDialog(
      bisaPresensi ? 'Berhasil! 🎉' : 'Gagal ❌',
      bisaPresensi
          ? 'Presensi keluar berhasil dilakukan!'
          : 'Anda berada di luar area presensi.',
      isError: !bisaPresensi,
    );
  }

  void _showDialog(String title, String content, {required bool isError}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: TextStyle(
            color: isError ? const Color(0xFFEF4444) : const Color(0xFF10B981),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceHistory() {
    // Dummy data jika kosong
    final data = _absensiList.isEmpty
        ? [
            {
              'tanggal': '2025-07-18',
              'waktu_masuk': '07:00',
              'waktu_keluar': '15:00',
              'keterangan': 'Hadir',
            },
            {
              'tanggal': '2025-07-17',
              'waktu_masuk': '07:12',
              'waktu_keluar': '15:05',
              'keterangan': 'Hadir',
            },
          ]
        : _absensiList;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Riwayat Presensi',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 16),

          // Header
          Row(
            children: const [
              Expanded(
                flex: 3,
                child: Text(
                  'Tanggal',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    'Jam Masuk',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Center(
                  child: Text(
                    'Jam Keluar',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Keterangan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Divider(thickness: 1),
          const SizedBox(height: 8),

          // Data Presensi
          ...data.map((item) {
            final tanggal = item['tanggal'] ?? '-';
            final waktuMasuk = item['waktu_masuk'] ?? '-';
            final waktuKeluar = item['waktu_keluar'] ?? '-';
            final keterangan = item['keterangan'] ?? '-';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                children: [
                  Expanded(flex: 3, child: Text(tanggal)),
                  Expanded(flex: 3, child: Center(child: Text(waktuMasuk))),
                  Expanded(flex: 3, child: Center(child: Text(waktuKeluar))),
                  Expanded(
                    flex: 3,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        keterangan,
                        style: TextStyle(
                          color: keterangan.toLowerCase() == 'hadir'
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
