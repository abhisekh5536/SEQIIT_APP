import '../models/society_models.dart';

Resident _r(
  String name,
  ResidentRole role, {
  String? phone,
  String? email,
  String? relation,
  String? vehicle,
  required String since,
  bool primary = false,
}) {
  return Resident(
    fullName: name,
    role: role,
    phone: phone,
    email: email,
    relation: relation,
    vehicle: vehicle,
    memberSince: since,
    isPrimary: primary,
  );
}

ResidenceUnit _u(
  String number,
  String tower,
  int floor,
  int bhk,
  int sqft,
  List<Resident> residents, {
  String? parking,
}) {
  return ResidenceUnit(
    number: number,
    tower: tower,
    floor: floor,
    bhk: bhk,
    sqft: sqft,
    parking: parking,
    residents: residents,
  );
}

/// Snapshot of the society's unit register, used by the resident directory.
/// Mirrors the record the committee maintains: flat, occupants, roles and
/// vehicles per household.
///
/// Towers differ in size on purpose — Tower B has four flats per floor,
/// which is why the signed-in member's flat is B-204 (hero card flat).
final List<ResidenceUnit> sampleUnits = [
  // ---- Tower A ----------------------------------------------------------
  _u(
    'A-101', 'A', 1, 2, 1125,
    [
      _r('Rajesh Mehta', ResidentRole.owner,
          phone: '+91 98110 28144',
          email: 'rajesh.mehta@gmail.com',
          vehicle: 'Maruti Suzuki Dzire · HR-26 CY 9034',
          since: 'Jan 2019',
          primary: true),
      _r('Sunita Mehta', ResidentRole.family,
          phone: '+91 84472 11809', relation: 'Spouse', since: 'Jan 2019'),
      _r('Aarav Mehta', ResidentRole.family,
          relation: 'Son', since: 'Jan 2019'),
    ],
    parking: 'A-01',
  ),
  _u(
    'A-102', 'A', 1, 3, 1420,
    [
      _r('Kavita Reddy', ResidentRole.owner,
          phone: '+91 99531 66207',
          email: 'kavita.reddy@outlook.com',
          vehicle: 'Honda City · HR-26 BC 1188',
          since: 'Apr 2018',
          primary: true),
      _r('Ankit Sharma', ResidentRole.tenant,
          phone: '+91 98108 77315',
          vehicle: 'Suzuki Access 125 · HR-26 AW 2082',
          since: 'Jul 2024',
          primary: true),
    ],
    parking: 'A-02',
  ),
  _u(
    'A-103', 'A', 2, 2, 1075,
    [
      _r('Deepak Bhatia', ResidentRole.owner,
          phone: '+91 98735 40021',
          email: 'deepak.bhatia@gmail.com',
          vehicle: 'Hyundai Creta · HR-26 DG 4511',
          since: 'Sep 2020',
          primary: true),
      _r('Neha Bhatia', ResidentRole.family,
          phone: '+91 99103 87654', relation: 'Spouse', since: 'Sep 2020'),
    ],
    parking: 'A-03',
  ),
  _u(
    'A-104', 'A', 2, 2, 1075,
    [
      _r('Sofia D\u2019Souza', ResidentRole.tenant,
          phone: '+91 77609 34128',
          email: 'sofia.dsouza@gmail.com',
          vehicle: 'Maruti Wagon R · HR-26 FF 0021',
          since: 'Feb 2025',
          primary: true),
    ],
    parking: 'A-04',
  ),
  _u(
    'A-105', 'A', 3, 3, 1420,
    [
      _r('G. S. Raghubir Singh', ResidentRole.owner,
          phone: '+91 98102 55573',
          vehicle: 'Toyota Innova Crysta · HR-26 AB 6342',
          since: 'Mar 2016',
          primary: true),
      _r('Poonam Singh', ResidentRole.family,
          phone: '+91 97111 03984', relation: 'Spouse', since: 'Mar 2016'),
    ],
    parking: 'A-05',
  ),
  _u('A-106', 'A', 3, 2, 1125, [], parking: 'A-06'),

  // ---- Tower B (four flats per floor) -----------------------------------
  _u(
    'B-101', 'B', 1, 3, 1410,
    [
      _r('Arjun Malhotra', ResidentRole.owner,
          phone: '+91 98210 88764',
          email: 'arjun.malhotra@gmail.com',
          vehicle: 'Skoda Slavia · HR-26 DL 7720',
          since: 'Dec 2017',
          primary: true),
      _r('Ishita Malhotra', ResidentRole.family,
          phone: '+91 98452 11930', relation: 'Spouse', since: 'Dec 2017'),
      _r('Vivaan Malhotra', ResidentRole.family,
          relation: 'Son', since: 'Dec 2017'),
    ],
    parking: 'B-01',
  ),
  _u(
    'B-102', 'B', 1, 2, 1090,
    [
      _r('Suresh Iyer', ResidentRole.owner,
          phone: '+91 98111 00477',
          email: 'suresh.iyer@gmail.com',
          vehicle: 'Tata Nexon · HR-26 FB 3091',
          since: 'Jun 2019',
          primary: true),
      _r('Lakshmi Iyer', ResidentRole.family,
          phone: '+91 98118 65320', relation: 'Spouse', since: 'Jun 2019'),
    ],
    parking: 'B-02',
  ),
  _u(
    'B-103', 'B', 1, 2, 1090,
    [
      _r('Mohammed Faisal', ResidentRole.tenant,
          phone: '+91 99536 21290',
          email: 'faisal.here@gmail.com',
          since: 'Jan 2023',
          primary: true),
      _r('Zoya Faisal', ResidentRole.family,
          phone: '+91 98105 99012', relation: 'Spouse', since: 'Jan 2023'),
    ],
    parking: 'B-03',
  ),
  _u(
    'B-104', 'B', 1, 2, 1090,
    [
      _r('Harsha Kulkarni', ResidentRole.tenant,
          phone: '+91 99870 23145',
          email: 'harsha.kulkarni@gmail.com',
          since: 'Nov 2024',
          primary: true),
    ],
    parking: 'B-04',
  ),
  _u(
    'B-201', 'B', 2, 3, 1410,
    [
      _r('Ashok Wadhwa', ResidentRole.owner,
          phone: '+91 98117 89954',
          vehicle: 'Renault Kwid · HR-26 KA 7166',
          since: 'Apr 2015',
          primary: true),
      _r('Ritu Wadhwa', ResidentRole.family,
          phone: '+91 98733 44178', relation: 'Spouse', since: 'Apr 2015'),
    ],
    parking: 'B-05',
  ),
  _u(
    'B-202', 'B', 2, 2, 1090,
    [
      _r('Priyanka Deshmukh', ResidentRole.tenant,
          phone: '+91 98700 51234',
          email: 'priyanka.d@yahoo.in',
          since: 'May 2025',
          primary: true),
    ],
    parking: 'B-06',
  ),
  _u('B-203', 'B', 2, 2, 1090, [], parking: 'B-07'),
  _u(
    'B-204', 'B', 2, 3, 1420,
    [
      _r('Saurabh Roy', ResidentRole.owner,
          phone: '+91 98108 22111',
          email: 'saurabh.roy@gmail.com',
          vehicle: 'Hyundai Verna · HR-26 BV 5512',
          since: 'Jul 2020',
          primary: true),
    ],
    parking: 'B-08',
  ),
  _u(
    'B-301', 'B', 3, 3, 1410,
    [
      _r('Gautam Deshpande', ResidentRole.owner,
          phone: '+91 98990 66218',
          email: 'gautam.d@gmail.com',
          vehicle: 'Volkswagen Virtus · HR-26 ED 3310',
          since: 'Sep 2021',
          primary: true),
      _r('Shilpa Deshpande', ResidentRole.family,
          phone: '+91 98990 66219', relation: 'Spouse', since: 'Sep 2021'),
    ],
    parking: 'B-09',
  ),
  _u('B-302', 'B', 3, 2, 1090, [], parking: 'B-10'),
  _u(
    'B-303', 'B', 3, 2, 1090,
    [
      _r('Imran Sheikh', ResidentRole.tenant,
          phone: '+91 99109 77330',
          email: 'imran.sheikh@gmail.com',
          vehicle: 'Yamaha FZ · HR-26 FH 1184',
          since: 'Nov 2024',
          primary: true),
    ],
    parking: 'B-11',
  ),
  _u(
    'B-304', 'B', 3, 3, 1410,
    [
      _r('Rekha Menon', ResidentRole.owner,
          phone: '+91 98470 22089',
          email: 'rekha.menon@gmail.com',
          since: 'Feb 2019',
          primary: true),
    ],
    parking: 'B-12',
  ),

  // ---- Tower C ----------------------------------------------------------
  _u(
    'C-101', 'C', 1, 2, 1090,
    [
      _r('Prakash Chandra', ResidentRole.owner,
          phone: '+91 98125 77008',
          email: 'prakash.chandra@yahoo.in',
          vehicle: 'Maruti Brezza · HR-26 EG 8823',
          since: 'Feb 2021',
          primary: true),
      _r('Meena Chandra', ResidentRole.family,
          phone: '+91 98125 77112', relation: 'Spouse', since: 'Feb 2021'),
    ],
    parking: 'C-01',
  ),
  _u(
    'C-102', 'C', 1, 3, 1395,
    [
      _r('Nandini Krishnan', ResidentRole.owner,
          phone: '+91 97405 60281',
          email: 'nandini.k@gmail.com',
          since: 'Jan 2018',
          primary: true),
      _r('Vivek Krishnan', ResidentRole.family,
          phone: '+91 97405 60282', relation: 'Spouse', since: 'Jan 2018'),
      _r('Sarthak Pillai', ResidentRole.tenant,
          phone: '+91 96255 84019',
          vehicle: 'KTM Duke 250 · HR-26 FB 5401',
          since: 'Mar 2025',
          primary: true),
    ],
    parking: 'C-02',
  ),
  _u(
    'C-103', 'C', 2, 2, 1090,
    [
      _r('Rohan Kapoor', ResidentRole.tenant,
          phone: '+91 98991 45116',
          email: 'rohan.kapoor@gmail.com',
          vehicle: 'Hyundai i20 · HR-26 CX 6678',
          since: 'Aug 2024',
          primary: true),
    ],
    parking: 'C-03',
  ),
  _u(
    'C-104', 'C', 2, 3, 1395,
    [
      _r('Sandeep Verma', ResidentRole.owner,
          phone: '+91 98183 66210',
          email: 'sandeep.verma@gmail.com',
          vehicle: 'Toyota Fortuner · HR-26 AE 9901',
          since: 'May 2017',
          primary: true),
      _r('Anjali Verma', ResidentRole.family,
          phone: '+91 98183 66212', relation: 'Spouse', since: 'May 2017'),
      _r('Riya Verma', ResidentRole.family,
          phone: '+91 99601 88372', relation: 'Daughter', since: 'May 2017'),
    ],
    parking: 'C-04',
  ),
  _u(
    'C-105', 'C', 3, 2, 1090,
    [
      _r('Farhan Qureshi', ResidentRole.owner,
          phone: '+91 98960 77530',
          email: 'farhan.qureshi@gmail.com',
          vehicle: 'Mahindra XUV300 · HR-26 DK 4521',
          since: 'Oct 2022',
          primary: true),
      _r('Salma Qureshi', ResidentRole.family,
          phone: '+91 98960 77531', relation: 'Spouse', since: 'Oct 2022'),
    ],
    parking: 'C-05',
  ),
  _u('C-106', 'C', 3, 3, 1395, [], parking: 'C-06'),
];