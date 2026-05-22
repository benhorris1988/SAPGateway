import 'models.dart';

// SAP ECC 6 seed data, HR + Expenses only. Field names match real DDIC
// codes (PERNR, NACHN, VORNA, ORGEH, BELNR, ...) so that consumers
// integrating against this mock get exactly the shape they'd see on a
// real ECC 6 system.

List<GatewayService> buildSeed() {
  return [
    _zhrEmployeeSrv(),
    _zhrOrgSrv(),
    _zhrTimeSrv(),
    _zhrPayrollSrv(),
    _zexpenseSrv(),
  ];
}

GatewayService _zhrEmployeeSrv() {
  final employee = EntityType(
    name: 'Employee',
    keys: ['Pernr'],
    properties: [
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Personnel Number'),
      Property(
          name: 'Nachn',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Last Name'),
      Property(
          name: 'Vorna',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'First Name'),
      Property(name: 'Gbdat', edmType: 'Edm.DateTime', label: 'Date of Birth'),
      Property(name: 'Begda', edmType: 'Edm.DateTime', label: 'Start Date'),
      Property(name: 'Endda', edmType: 'Edm.DateTime', label: 'End Date'),
      Property(
          name: 'Werks',
          edmType: 'Edm.String',
          maxLength: 4,
          label: 'Personnel Area'),
      Property(
          name: 'Persg',
          edmType: 'Edm.String',
          maxLength: 1,
          label: 'Employee Group'),
      Property(
          name: 'Persk',
          edmType: 'Edm.String',
          maxLength: 2,
          label: 'Employee Subgroup'),
    ],
  );
  final address = EntityType(
    name: 'Address',
    keys: ['Pernr', 'Subty'],
    properties: [
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Personnel Number'),
      Property(
          name: 'Subty',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 4,
          label: 'Address Type'),
      Property(
          name: 'Stras',
          edmType: 'Edm.String',
          maxLength: 60,
          label: 'Street'),
      Property(
          name: 'Ort01',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'City'),
      Property(
          name: 'Pstlz',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'Postal Code'),
      Property(
          name: 'Land1',
          edmType: 'Edm.String',
          maxLength: 3,
          label: 'Country'),
    ],
  );
  return GatewayService(
    name: 'ZHR_EMPLOYEE_SRV',
    namespace: 'ZHR_EMPLOYEE_SRV',
    description: 'HR Master Data — Employees & Addresses (PA0001/PA0006)',
    entityTypes: [employee, address],
    entitySets: [
      EntitySet(
        name: 'EmployeeSet',
        entityTypeName: 'Employee',
        rows: [
          {
            'Pernr': '00010001',
            'Nachn': 'Schmidt',
            'Vorna': 'Anna',
            'Gbdat': '1985-03-14T00:00:00',
            'Begda': '2010-09-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
            'Werks': '1000',
            'Persg': '1',
            'Persk': 'U1',
          },
          {
            'Pernr': '00010002',
            'Nachn': 'Müller',
            'Vorna': 'Hans',
            'Gbdat': '1978-11-22T00:00:00',
            'Begda': '2005-02-15T00:00:00',
            'Endda': '9999-12-31T00:00:00',
            'Werks': '1000',
            'Persg': '1',
            'Persk': 'U2',
          },
          {
            'Pernr': '00010003',
            'Nachn': 'Khan',
            'Vorna': 'Priya',
            'Gbdat': '1990-07-09T00:00:00',
            'Begda': '2018-06-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
            'Werks': '2000',
            'Persg': '1',
            'Persk': 'U1',
          },
          {
            'Pernr': '00010004',
            'Nachn': 'Brown',
            'Vorna': 'Michael',
            'Gbdat': '1982-01-30T00:00:00',
            'Begda': '2012-04-10T00:00:00',
            'Endda': '9999-12-31T00:00:00',
            'Werks': '3000',
            'Persg': '1',
            'Persk': 'U3',
          },
          {
            'Pernr': '00010005',
            'Nachn': 'Tanaka',
            'Vorna': 'Yui',
            'Gbdat': '1995-05-18T00:00:00',
            'Begda': '2021-10-04T00:00:00',
            'Endda': '9999-12-31T00:00:00',
            'Werks': '4000',
            'Persg': '1',
            'Persk': 'U1',
          },
        ],
      ),
      EntitySet(
        name: 'AddressSet',
        entityTypeName: 'Address',
        rows: [
          {
            'Pernr': '00010001',
            'Subty': '0001',
            'Stras': 'Maximilianstraße 12',
            'Ort01': 'München',
            'Pstlz': '80539',
            'Land1': 'DE',
          },
          {
            'Pernr': '00010002',
            'Subty': '0001',
            'Stras': 'Kurfürstendamm 188',
            'Ort01': 'Berlin',
            'Pstlz': '10707',
            'Land1': 'DE',
          },
          {
            'Pernr': '00010003',
            'Subty': '0001',
            'Stras': '221B Baker Street',
            'Ort01': 'London',
            'Pstlz': 'NW1 6XE',
            'Land1': 'GB',
          },
          {
            'Pernr': '00010004',
            'Subty': '0001',
            'Stras': '350 5th Avenue',
            'Ort01': 'New York',
            'Pstlz': '10118',
            'Land1': 'US',
          },
          {
            'Pernr': '00010005',
            'Subty': '0001',
            'Stras': '1-1-2 Oshiage',
            'Ort01': 'Tokyo',
            'Pstlz': '131-0045',
            'Land1': 'JP',
          },
        ],
      ),
    ],
  );
}

GatewayService _zhrOrgSrv() {
  final orgUnit = EntityType(
    name: 'OrgUnit',
    keys: ['Orgeh'],
    properties: [
      Property(
          name: 'Orgeh',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Organisational Unit'),
      Property(
          name: 'Orgtx',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
      Property(
          name: 'Plvar',
          edmType: 'Edm.String',
          maxLength: 2,
          label: 'Plan Version'),
      Property(name: 'Begda', edmType: 'Edm.DateTime', label: 'Start Date'),
      Property(name: 'Endda', edmType: 'Edm.DateTime', label: 'End Date'),
    ],
  );
  final position = EntityType(
    name: 'Position',
    keys: ['Plans'],
    properties: [
      Property(
          name: 'Plans',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Position'),
      Property(
          name: 'Plstx',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
      Property(
          name: 'Orgeh',
          edmType: 'Edm.String',
          maxLength: 8,
          label: 'Organisational Unit'),
      Property(
          name: 'Stell',
          edmType: 'Edm.String',
          maxLength: 8,
          label: 'Job'),
      Property(name: 'Begda', edmType: 'Edm.DateTime', label: 'Start Date'),
      Property(name: 'Endda', edmType: 'Edm.DateTime', label: 'End Date'),
    ],
  );
  final job = EntityType(
    name: 'Job',
    keys: ['Stell'],
    properties: [
      Property(
          name: 'Stell',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Job'),
      Property(
          name: 'Stltx',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
      Property(name: 'Begda', edmType: 'Edm.DateTime', label: 'Start Date'),
      Property(name: 'Endda', edmType: 'Edm.DateTime', label: 'End Date'),
    ],
  );
  return GatewayService(
    name: 'ZHR_ORG_SRV',
    namespace: 'ZHR_ORG_SRV',
    description: 'HR Organisational Management — OrgUnits, Positions, Jobs',
    entityTypes: [orgUnit, position, job],
    entitySets: [
      EntitySet(
        name: 'OrgUnitSet',
        entityTypeName: 'OrgUnit',
        rows: [
          {
            'Orgeh': '50000001',
            'Orgtx': 'Headquarters',
            'Plvar': '01',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Orgeh': '50000010',
            'Orgtx': 'Finance & Controlling',
            'Plvar': '01',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Orgeh': '50000020',
            'Orgtx': 'IT Services',
            'Plvar': '01',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Orgeh': '50000030',
            'Orgtx': 'Sales EMEA',
            'Plvar': '01',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
        ],
      ),
      EntitySet(
        name: 'PositionSet',
        entityTypeName: 'Position',
        rows: [
          {
            'Plans': '60000001',
            'Plstx': 'Chief Financial Officer',
            'Orgeh': '50000010',
            'Stell': '70000001',
            'Begda': '2010-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Plans': '60000002',
            'Plstx': 'Senior Accountant',
            'Orgeh': '50000010',
            'Stell': '70000002',
            'Begda': '2010-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Plans': '60000010',
            'Plstx': 'Software Engineer',
            'Orgeh': '50000020',
            'Stell': '70000010',
            'Begda': '2012-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Plans': '60000020',
            'Plstx': 'Sales Manager',
            'Orgeh': '50000030',
            'Stell': '70000020',
            'Begda': '2008-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
        ],
      ),
      EntitySet(
        name: 'JobSet',
        entityTypeName: 'Job',
        rows: [
          {
            'Stell': '70000001',
            'Stltx': 'Executive',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Stell': '70000002',
            'Stltx': 'Accountant',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Stell': '70000010',
            'Stltx': 'Engineer',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
          {
            'Stell': '70000020',
            'Stltx': 'Sales Professional',
            'Begda': '2000-01-01T00:00:00',
            'Endda': '9999-12-31T00:00:00',
          },
        ],
      ),
    ],
  );
}

GatewayService _zhrTimeSrv() {
  final absence = EntityType(
    name: 'Absence',
    keys: ['Pernr', 'Begda', 'Awart'],
    properties: [
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Personnel Number'),
      Property(
          name: 'Awart',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 4,
          label: 'Absence Type'),
      Property(
          name: 'Begda',
          edmType: 'Edm.DateTime',
          nullable: false,
          label: 'Start Date'),
      Property(name: 'Endda', edmType: 'Edm.DateTime', label: 'End Date'),
      Property(
          name: 'Abwtg',
          edmType: 'Edm.Decimal',
          precision: 6,
          scale: 2,
          label: 'Absence Days'),
    ],
  );
  final timesheet = EntityType(
    name: 'Timesheet',
    keys: ['Pernr', 'Workd'],
    properties: [
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Personnel Number'),
      Property(
          name: 'Workd',
          edmType: 'Edm.DateTime',
          nullable: false,
          label: 'Work Date'),
      Property(
          name: 'Stdaz',
          edmType: 'Edm.Decimal',
          precision: 5,
          scale: 2,
          label: 'Hours Worked'),
      Property(
          name: 'Lstar',
          edmType: 'Edm.String',
          maxLength: 6,
          label: 'Activity Type'),
      Property(
          name: 'Kostl',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'Cost Center'),
    ],
  );
  return GatewayService(
    name: 'ZHR_TIME_SRV',
    namespace: 'ZHR_TIME_SRV',
    description: 'HR Time Management — Absences & Timesheets',
    entityTypes: [absence, timesheet],
    entitySets: [
      EntitySet(
        name: 'AbsenceSet',
        entityTypeName: 'Absence',
        rows: [
          {
            'Pernr': '00010001',
            'Awart': '0100',
            'Begda': '2026-03-09T00:00:00',
            'Endda': '2026-03-13T00:00:00',
            'Abwtg': '5.00',
          },
          {
            'Pernr': '00010002',
            'Awart': '0200',
            'Begda': '2026-04-20T00:00:00',
            'Endda': '2026-04-22T00:00:00',
            'Abwtg': '3.00',
          },
          {
            'Pernr': '00010003',
            'Awart': '0100',
            'Begda': '2026-05-04T00:00:00',
            'Endda': '2026-05-15T00:00:00',
            'Abwtg': '10.00',
          },
        ],
      ),
      EntitySet(
        name: 'TimesheetSet',
        entityTypeName: 'Timesheet',
        rows: [
          {
            'Pernr': '00010001',
            'Workd': '2026-05-18T00:00:00',
            'Stdaz': '8.00',
            'Lstar': 'PROJ01',
            'Kostl': '0000010000',
          },
          {
            'Pernr': '00010001',
            'Workd': '2026-05-19T00:00:00',
            'Stdaz': '8.00',
            'Lstar': 'PROJ01',
            'Kostl': '0000010000',
          },
          {
            'Pernr': '00010002',
            'Workd': '2026-05-18T00:00:00',
            'Stdaz': '7.50',
            'Lstar': 'PROJ02',
            'Kostl': '0000020000',
          },
          {
            'Pernr': '00010004',
            'Workd': '2026-05-19T00:00:00',
            'Stdaz': '8.00',
            'Lstar': 'PROJ03',
            'Kostl': '0000030000',
          },
        ],
      ),
    ],
  );
}

GatewayService _zhrPayrollSrv() {
  final payrollResult = EntityType(
    name: 'PayrollResult',
    keys: ['Pernr', 'Seqnr'],
    properties: [
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 8,
          label: 'Personnel Number'),
      Property(
          name: 'Seqnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 5,
          label: 'Sequence Number'),
      Property(
          name: 'Fpper',
          edmType: 'Edm.String',
          maxLength: 6,
          label: 'For-Period (YYYYMM)'),
      Property(
          name: 'Payty',
          edmType: 'Edm.String',
          maxLength: 1,
          label: 'Payroll Type'),
      Property(
          name: 'Betrg',
          edmType: 'Edm.Decimal',
          precision: 13,
          scale: 2,
          label: 'Amount'),
      Property(
          name: 'Waers',
          edmType: 'Edm.String',
          maxLength: 5,
          label: 'Currency'),
    ],
  );
  final wageType = EntityType(
    name: 'WageType',
    keys: ['Lgart'],
    properties: [
      Property(
          name: 'Lgart',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 4,
          label: 'Wage Type'),
      Property(
          name: 'Lgtxt',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
    ],
  );
  return GatewayService(
    name: 'ZHR_PAYROLL_SRV',
    namespace: 'ZHR_PAYROLL_SRV',
    description: 'HR Payroll — Results & Wage Types',
    entityTypes: [payrollResult, wageType],
    entitySets: [
      EntitySet(
        name: 'PayrollResultSet',
        entityTypeName: 'PayrollResult',
        rows: [
          {
            'Pernr': '00010001',
            'Seqnr': '00001',
            'Fpper': '202604',
            'Payty': 'A',
            'Betrg': '5200.00',
            'Waers': 'EUR',
          },
          {
            'Pernr': '00010002',
            'Seqnr': '00001',
            'Fpper': '202604',
            'Payty': 'A',
            'Betrg': '6100.00',
            'Waers': 'EUR',
          },
          {
            'Pernr': '00010003',
            'Seqnr': '00001',
            'Fpper': '202604',
            'Payty': 'A',
            'Betrg': '4700.00',
            'Waers': 'GBP',
          },
          {
            'Pernr': '00010004',
            'Seqnr': '00001',
            'Fpper': '202604',
            'Payty': 'A',
            'Betrg': '7200.00',
            'Waers': 'USD',
          },
        ],
      ),
      EntitySet(
        name: 'WageTypeSet',
        entityTypeName: 'WageType',
        rows: [
          {'Lgart': '1000', 'Lgtxt': 'Base Salary'},
          {'Lgart': '1100', 'Lgtxt': 'Overtime'},
          {'Lgart': '1200', 'Lgtxt': 'Bonus'},
          {'Lgart': '2000', 'Lgtxt': 'Income Tax'},
          {'Lgart': '2100', 'Lgtxt': 'Social Security'},
        ],
      ),
    ],
  );
}

GatewayService _zexpenseSrv() {
  final expense = EntityType(
    name: 'Expense',
    keys: ['Belnr'],
    properties: [
      Property(
          name: 'Belnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Document Number'),
      Property(
          name: 'Pernr',
          edmType: 'Edm.String',
          maxLength: 8,
          label: 'Personnel Number'),
      Property(name: 'Bldat', edmType: 'Edm.DateTime', label: 'Document Date'),
      Property(
          name: 'Wrbtr',
          edmType: 'Edm.Decimal',
          precision: 13,
          scale: 2,
          label: 'Amount'),
      Property(
          name: 'Waers',
          edmType: 'Edm.String',
          maxLength: 5,
          label: 'Currency'),
      Property(
          name: 'Kostl',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'Cost Center'),
      Property(
          name: 'Saknr',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'GL Account'),
      Property(
          name: 'Sgtxt',
          edmType: 'Edm.String',
          maxLength: 50,
          label: 'Item Text'),
      Property(
          name: 'Status',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'Posting Status'),
    ],
  );
  return GatewayService(
    name: 'ZEXPENSE_SRV',
    namespace: 'ZEXPENSE_SRV',
    description: 'Employee Expenses (write-back enabled)',
    entityTypes: [expense],
    entitySets: [
      EntitySet(
        name: 'ExpenseSet',
        entityTypeName: 'Expense',
        rows: [
          {
            'Belnr': '1900000001',
            'Pernr': '00010001',
            'Bldat': '2026-05-02T00:00:00',
            'Wrbtr': '42.50',
            'Waers': 'GBP',
            'Kostl': '0000010000',
            'Saknr': '0000500000',
            'Sgtxt': 'Client lunch - London',
            'Status': 'POSTED',
          },
          {
            'Belnr': '1900000002',
            'Pernr': '00010002',
            'Bldat': '2026-05-05T00:00:00',
            'Wrbtr': '128.00',
            'Waers': 'EUR',
            'Kostl': '0000020000',
            'Saknr': '0000500000',
            'Sgtxt': 'Taxi Munich airport',
            'Status': 'POSTED',
          },
          {
            'Belnr': '1900000003',
            'Pernr': '00010001',
            'Bldat': '2026-05-18T00:00:00',
            'Wrbtr': '865.00',
            'Waers': 'USD',
            'Kostl': '0000030000',
            'Saknr': '0000500000',
            'Sgtxt': 'Hotel - NYC offsite',
            'Status': 'SUBMITTED',
          },
        ],
      ),
    ],
  );
}
