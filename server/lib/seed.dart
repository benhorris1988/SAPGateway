import 'models.dart';

// SAP-style seed: services, EntityTypes, EntitySets, and a few rows each.
// Field names match SAP source-system codes (KUNNR, MATNR, VBELN, ...) the way
// they would on a real ECC 6.0 NetWeaver Gateway service.

List<GatewayService> buildSeed() {
  return [
    _zsalesSrv(),
    _zmaterialSrv(),
    _zvendorSrv(),
    _zpurchSrv(),
    _zpriceSrv(),
    _zstockSrv(),
    _zfinSrv(),
    _zexpenseSrv(),
  ];
}

GatewayService _zsalesSrv() {
  final customer = EntityType(
    name: 'Customer',
    keys: ['Kunnr'],
    properties: [
      Property(
          name: 'Kunnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Customer Number'),
      Property(
          name: 'Name1', edmType: 'Edm.String', maxLength: 40, label: 'Name'),
      Property(
          name: 'Land1', edmType: 'Edm.String', maxLength: 3, label: 'Country'),
      Property(
          name: 'Ktokd',
          edmType: 'Edm.String',
          maxLength: 4,
          label: 'Account Group'),
      Property(name: 'Erdat', edmType: 'Edm.DateTime', label: 'Created On'),
    ],
  );
  final salesOrder = EntityType(
    name: 'SalesOrder',
    keys: ['Vbeln'],
    properties: [
      Property(
          name: 'Vbeln',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Sales Document'),
      Property(
          name: 'Kunnr',
          edmType: 'Edm.String',
          maxLength: 10,
          label: 'Sold-To'),
      Property(name: 'Audat', edmType: 'Edm.DateTime', label: 'Document Date'),
      Property(
          name: 'Netwr',
          edmType: 'Edm.Decimal',
          precision: 15,
          scale: 2,
          label: 'Net Value'),
      Property(
          name: 'Waerk',
          edmType: 'Edm.String',
          maxLength: 5,
          label: 'Currency'),
    ],
  );
  final salesOrderItem = EntityType(
    name: 'SalesOrderItem',
    keys: ['Vbeln', 'Posnr'],
    properties: [
      Property(
          name: 'Vbeln',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Sales Document'),
      Property(
          name: 'Posnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 6,
          label: 'Item'),
      Property(
          name: 'Matnr',
          edmType: 'Edm.String',
          maxLength: 18,
          label: 'Material'),
      Property(
          name: 'Kwmeng',
          edmType: 'Edm.Decimal',
          precision: 13,
          scale: 3,
          label: 'Order Quantity'),
      Property(
          name: 'Vrkme',
          edmType: 'Edm.String',
          maxLength: 3,
          label: 'Sales Unit'),
    ],
  );

  return GatewayService(
    name: 'ZSALES_SRV',
    namespace: 'ZSALES_SRV',
    description: 'Sales Master & Transactions',
    entityTypes: [customer, salesOrder, salesOrderItem],
    entitySets: [
      EntitySet(
        name: 'CustomerSet',
        entityTypeName: 'Customer',
        rows: [
          {
            'Kunnr': '0000001000',
            'Name1': 'ACME Corp',
            'Land1': 'US',
            'Ktokd': 'KUNA',
            'Erdat': '2018-04-12T00:00:00'
          },
          {
            'Kunnr': '0000001001',
            'Name1': 'Globex Ltd',
            'Land1': 'GB',
            'Ktokd': 'KUNA',
            'Erdat': '2019-06-22T00:00:00'
          },
          {
            'Kunnr': '0000001002',
            'Name1': 'Initech',
            'Land1': 'US',
            'Ktokd': 'KUNA',
            'Erdat': '2020-01-08T00:00:00'
          },
          {
            'Kunnr': '0000001003',
            'Name1': 'Soylent GmbH',
            'Land1': 'DE',
            'Ktokd': 'KUNB',
            'Erdat': '2021-11-30T00:00:00'
          },
          {
            'Kunnr': '0000001004',
            'Name1': 'Umbrella SA',
            'Land1': 'FR',
            'Ktokd': 'KUNA',
            'Erdat': '2022-03-14T00:00:00'
          },
          {
            'Kunnr': '0000001005',
            'Name1': 'Hooli Asia Pte Ltd',
            'Land1': 'SG',
            'Ktokd': 'KUNA',
            'Erdat': '2023-08-01T00:00:00'
          },
        ],
      ),
      EntitySet(
        name: 'SalesOrderSet',
        entityTypeName: 'SalesOrder',
        rows: [
          {
            'Vbeln': '0000010001',
            'Kunnr': '0000001000',
            'Audat': '2026-05-10T00:00:00',
            'Netwr': '12450.00',
            'Waerk': 'USD'
          },
          {
            'Vbeln': '0000010002',
            'Kunnr': '0000001001',
            'Audat': '2026-05-11T00:00:00',
            'Netwr': '8800.50',
            'Waerk': 'GBP'
          },
          {
            'Vbeln': '0000010003',
            'Kunnr': '0000001003',
            'Audat': '2026-05-12T00:00:00',
            'Netwr': '21000.00',
            'Waerk': 'EUR'
          },
          {
            'Vbeln': '0000010004',
            'Kunnr': '0000001002',
            'Audat': '2026-05-13T00:00:00',
            'Netwr': '450.00',
            'Waerk': 'USD'
          },
        ],
      ),
      EntitySet(
        name: 'SalesOrderItemSet',
        entityTypeName: 'SalesOrderItem',
        rows: [
          {
            'Vbeln': '0000010001',
            'Posnr': '000010',
            'Matnr': 'M-0001',
            'Kwmeng': '5.000',
            'Vrkme': 'EA'
          },
          {
            'Vbeln': '0000010001',
            'Posnr': '000020',
            'Matnr': 'M-0002',
            'Kwmeng': '2.000',
            'Vrkme': 'EA'
          },
          {
            'Vbeln': '0000010002',
            'Posnr': '000010',
            'Matnr': 'M-0003',
            'Kwmeng': '10.000',
            'Vrkme': 'EA'
          },
          {
            'Vbeln': '0000010003',
            'Posnr': '000010',
            'Matnr': 'M-0001',
            'Kwmeng': '50.000',
            'Vrkme': 'EA'
          },
          {
            'Vbeln': '0000010003',
            'Posnr': '000020',
            'Matnr': 'M-0004',
            'Kwmeng': '12.000',
            'Vrkme': 'EA'
          },
          {
            'Vbeln': '0000010004',
            'Posnr': '000010',
            'Matnr': 'M-0002',
            'Kwmeng': '1.000',
            'Vrkme': 'EA'
          },
        ],
      ),
    ],
  );
}

GatewayService _zmaterialSrv() {
  final material = EntityType(
    name: 'Material',
    keys: ['Matnr'],
    properties: [
      Property(
          name: 'Matnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 18,
          label: 'Material Number'),
      Property(
          name: 'Maktx',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
      Property(
          name: 'Matkl',
          edmType: 'Edm.String',
          maxLength: 9,
          label: 'Material Group'),
      Property(
          name: 'Meins',
          edmType: 'Edm.String',
          maxLength: 3,
          label: 'Base UoM'),
      Property(
          name: 'Mtart',
          edmType: 'Edm.String',
          maxLength: 4,
          label: 'Material Type'),
    ],
  );
  return GatewayService(
    name: 'ZMATERIAL_SRV',
    namespace: 'ZMATERIAL_SRV',
    description: 'Material Master',
    entityTypes: [material],
    entitySets: [
      EntitySet(
        name: 'MaterialSet',
        entityTypeName: 'Material',
        rows: [
          {
            'Matnr': 'M-0001',
            'Maktx': 'Steel Pipe DN50',
            'Matkl': '0010',
            'Meins': 'M',
            'Mtart': 'ROH'
          },
          {
            'Matnr': 'M-0002',
            'Maktx': 'Steel Pipe DN100',
            'Matkl': '0010',
            'Meins': 'M',
            'Mtart': 'ROH'
          },
          {
            'Matnr': 'M-0003',
            'Maktx': 'Valve Type A',
            'Matkl': '0020',
            'Meins': 'EA',
            'Mtart': 'HALB'
          },
          {
            'Matnr': 'M-0004',
            'Maktx': 'Gasket Set',
            'Matkl': '0020',
            'Meins': 'EA',
            'Mtart': 'HALB'
          },
          {
            'Matnr': 'M-0005',
            'Maktx': 'Bracket Assembly',
            'Matkl': '0030',
            'Meins': 'EA',
            'Mtart': 'FERT'
          },
        ],
      ),
    ],
  );
}

GatewayService _zvendorSrv() {
  final vendor = EntityType(
    name: 'Vendor',
    keys: ['Lifnr'],
    properties: [
      Property(
          name: 'Lifnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Vendor Number'),
      Property(
          name: 'Name1', edmType: 'Edm.String', maxLength: 40, label: 'Name'),
      Property(
          name: 'Land1', edmType: 'Edm.String', maxLength: 3, label: 'Country'),
      Property(
          name: 'Stcd1', edmType: 'Edm.String', maxLength: 16, label: 'Tax ID'),
    ],
  );
  return GatewayService(
    name: 'ZVENDOR_SRV',
    namespace: 'ZVENDOR_SRV',
    description: 'Vendor Master',
    entityTypes: [vendor],
    entitySets: [
      EntitySet(
        name: 'VendorSet',
        entityTypeName: 'Vendor',
        rows: [
          {
            'Lifnr': '0000100001',
            'Name1': 'Tyrell Supplies',
            'Land1': 'US',
            'Stcd1': '12-3456789'
          },
          {
            'Lifnr': '0000100002',
            'Name1': 'Nakatomi Parts',
            'Land1': 'JP',
            'Stcd1': '7000012345678'
          },
          {
            'Lifnr': '0000100003',
            'Name1': 'Wayland Logistik',
            'Land1': 'DE',
            'Stcd1': 'DE123456789'
          },
        ],
      ),
    ],
  );
}

GatewayService _zpurchSrv() {
  final po = EntityType(
    name: 'PurchaseOrder',
    keys: ['Ebeln'],
    properties: [
      Property(
          name: 'Ebeln',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'PO Number'),
      Property(
          name: 'Lifnr', edmType: 'Edm.String', maxLength: 10, label: 'Vendor'),
      Property(name: 'Bedat', edmType: 'Edm.DateTime', label: 'PO Date'),
      Property(
          name: 'Waers',
          edmType: 'Edm.String',
          maxLength: 5,
          label: 'Currency'),
    ],
  );
  return GatewayService(
    name: 'ZPURCH_SRV',
    namespace: 'ZPURCH_SRV',
    description: 'Purchase Orders',
    entityTypes: [po],
    entitySets: [
      EntitySet(
        name: 'PurchaseOrderSet',
        entityTypeName: 'PurchaseOrder',
        rows: [
          {
            'Ebeln': '4500000001',
            'Lifnr': '0000100001',
            'Bedat': '2026-04-30T00:00:00',
            'Waers': 'USD'
          },
          {
            'Ebeln': '4500000002',
            'Lifnr': '0000100002',
            'Bedat': '2026-05-02T00:00:00',
            'Waers': 'JPY'
          },
          {
            'Ebeln': '4500000003',
            'Lifnr': '0000100003',
            'Bedat': '2026-05-04T00:00:00',
            'Waers': 'EUR'
          },
        ],
      ),
    ],
  );
}

GatewayService _zpriceSrv() {
  final cond = EntityType(
    name: 'PricingCondition',
    keys: ['Knumh'],
    properties: [
      Property(
          name: 'Knumh',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Condition Record No.'),
      Property(
          name: 'Kschl',
          edmType: 'Edm.String',
          maxLength: 4,
          label: 'Condition Type'),
      Property(name: 'Datab', edmType: 'Edm.DateTime', label: 'Valid From'),
      Property(name: 'Datbi', edmType: 'Edm.DateTime', label: 'Valid To'),
      Property(
          name: 'Kbetr',
          edmType: 'Edm.Decimal',
          precision: 11,
          scale: 2,
          label: 'Rate'),
    ],
  );
  return GatewayService(
    name: 'ZPRICE_SRV',
    namespace: 'ZPRICE_SRV',
    description: 'Pricing Conditions',
    entityTypes: [cond],
    entitySets: [
      EntitySet(
        name: 'ConditionSet',
        entityTypeName: 'PricingCondition',
        rows: [
          {
            'Knumh': '0000000001',
            'Kschl': 'PR00',
            'Datab': '2026-01-01T00:00:00',
            'Datbi': '2026-12-31T00:00:00',
            'Kbetr': '199.00'
          },
          {
            'Knumh': '0000000002',
            'Kschl': 'K007',
            'Datab': '2026-01-01T00:00:00',
            'Datbi': '2026-06-30T00:00:00',
            'Kbetr': '-5.00'
          },
        ],
      ),
    ],
  );
}

GatewayService _zstockSrv() {
  final stock = EntityType(
    name: 'Stock',
    keys: ['Matnr', 'Werks'],
    properties: [
      Property(
          name: 'Matnr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 18,
          label: 'Material'),
      Property(
          name: 'Werks',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 4,
          label: 'Plant'),
      Property(
          name: 'Labst',
          edmType: 'Edm.Decimal',
          precision: 13,
          scale: 3,
          label: 'Unrestricted Stock'),
      Property(
          name: 'Meins', edmType: 'Edm.String', maxLength: 3, label: 'UoM'),
    ],
  );
  return GatewayService(
    name: 'ZSTOCK_SRV',
    namespace: 'ZSTOCK_SRV',
    description: 'Inventory',
    entityTypes: [stock],
    entitySets: [
      EntitySet(
        name: 'StockSet',
        entityTypeName: 'Stock',
        rows: [
          {
            'Matnr': 'M-0001',
            'Werks': '1000',
            'Labst': '1200.000',
            'Meins': 'M'
          },
          {
            'Matnr': 'M-0002',
            'Werks': '1000',
            'Labst': '450.000',
            'Meins': 'M'
          },
          {
            'Matnr': 'M-0003',
            'Werks': '1000',
            'Labst': '80.000',
            'Meins': 'EA'
          },
          {
            'Matnr': 'M-0004',
            'Werks': '2000',
            'Labst': '300.000',
            'Meins': 'EA'
          },
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
          label: 'Employee Number'),
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

GatewayService _zfinSrv() {
  final glAccount = EntityType(
    name: 'GLAccount',
    keys: ['Saknr'],
    properties: [
      Property(
          name: 'Saknr',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'GL Account'),
      Property(
          name: 'Txt50',
          edmType: 'Edm.String',
          maxLength: 50,
          label: 'Description'),
      Property(
          name: 'Mwskz',
          edmType: 'Edm.String',
          maxLength: 2,
          label: 'Tax Code'),
    ],
  );
  final costCenter = EntityType(
    name: 'CostCenter',
    keys: ['Kostl'],
    properties: [
      Property(
          name: 'Kostl',
          edmType: 'Edm.String',
          nullable: false,
          maxLength: 10,
          label: 'Cost Center'),
      Property(
          name: 'Ktext',
          edmType: 'Edm.String',
          maxLength: 40,
          label: 'Description'),
      Property(
          name: 'Bukrs',
          edmType: 'Edm.String',
          maxLength: 4,
          label: 'Company Code'),
    ],
  );
  return GatewayService(
    name: 'ZFIN_SRV',
    namespace: 'ZFIN_SRV',
    description: 'Finance Master',
    entityTypes: [glAccount, costCenter],
    entitySets: [
      EntitySet(
        name: 'GLAccountSet',
        entityTypeName: 'GLAccount',
        rows: [
          {'Saknr': '0000400000', 'Txt50': 'Revenue Domestic', 'Mwskz': 'A1'},
          {'Saknr': '0000400100', 'Txt50': 'Revenue Export', 'Mwskz': 'A0'},
          {'Saknr': '0000500000', 'Txt50': 'Cost of Goods Sold', 'Mwskz': ''},
          {'Saknr': '0000800000', 'Txt50': 'Bank Cash USD', 'Mwskz': ''},
        ],
      ),
      EntitySet(
        name: 'CostCenterSet',
        entityTypeName: 'CostCenter',
        rows: [
          {'Kostl': '0000010000', 'Ktext': 'Headquarters', 'Bukrs': '1000'},
          {'Kostl': '0000020000', 'Ktext': 'Plant Munich', 'Bukrs': '1000'},
          {'Kostl': '0000030000', 'Ktext': 'Sales NA', 'Bukrs': '2000'},
        ],
      ),
    ],
  );
}
