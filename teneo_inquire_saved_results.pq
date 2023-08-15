[Version = "7.2.0-SP1"]
section teneo_inquire_saved_results;

[DataSource.Kind="teneo_inquire_saved_results", Publish="teneo_inquire_saved_results.Publish"]
shared teneo_inquire_saved_results.Contents = (url as text, lds as text) as table =>
    let
       results = GetResults(url, lds),
       tableResult = #table({"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"}, results),
       tableNav = Table.ToNavigationTable(tableResult, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
       tableNav;

// Data Source Kind description
teneo_inquire_saved_results = [
    Authentication = [
        //Key = [],
        UsernamePassword = []
        // Windows = [],
        //Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
teneo_inquire_saved_results.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://developers.teneo.ai/",
    SourceImage = teneo_inquire_saved_results.Icons,
    SourceTypeImage = teneo_inquire_saved_results.Icons
];

teneo_inquire_saved_results.Icons = [
    Icon16 = { Extension.Contents("teneo_saved_results16.png"), Extension.Contents("teneo_saved_results20.png"), Extension.Contents("teneo_saved_results24.png"), Extension.Contents("teneo_saved_results32.png") },
    Icon32 = { Extension.Contents("teneo_saved_results32.png"), Extension.Contents("teneo_saved_results40.png"), Extension.Contents("teneo_saved_results48.png"), Extension.Contents("teneo_saved_results64.png") }
];

authType = "Bearer ";

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta
        [
            NavigationTable.NameColumn = nameColumn,
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn,
            Preview.DelayColumn = itemNameColumn,
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;

Login = (url as text, username as text, password as text) as text =>
    let
        json = Json.FromValue([user = username, username = username, pass = password, password = password]),
        authSource = Web.Contents(url,
        [
            RelativePath = "/auth/login",
            Headers = [#"Content-Type" = "application/json"],
            Content = json
        ]
        ),
        authToken = Text.FromBinary(authSource),
        token = if Text.StartsWith(authToken, """") then Text.BetweenDelimiters(authToken, """", """") else authToken
    in
        token;

SharedQueries = (url as text, lds as text, authToken as text) as list =>
    let
        path = Text.Combine({"/saved-results/", lds}),
        source = Web.Contents(url, [
            RelativePath = path,
            Headers = [Authorization = Text.Combine({authType, authToken}), #"Content-Type" = "application/json"],
            Timeout = #duration(1, 0, 0, 0)
        ]),
        json = Json.Document(source)
    in
        json;

GetIds = (ar as list) as table =>
    let
        ids = Table.FromRecords(ar)
    in
        ids;

ExtractData = (url as text, lds as text, authToken as text, id as text) as list =>
    let
        path = Text.Combine({"/saved-results/export", "/", lds, "/", id}),
        source = Web.Contents(url, [
            RelativePath = path,
            Query = [format = "json", timeout = "1200000"],
            Headers = [Authorization = Text.Combine({authType, authToken}), #"Accept" = "application/octet-stream"],
            IsRetry = true,
            Timeout = #duration(1, 0, 0, 0)
        ])
    in
        Json.Document(source);

GetColumnDataType = (indata as table) as record =>
    let
        names = Table.ColumnNames(indata),
        textList = List.Select(names, each Text.StartsWith(_, "s.") or Text.StartsWith(_, "s:")),
        dateList = List.Select(names, each Text.StartsWith(_, "d.") or Text.StartsWith(_, "d:")),
        dateTimeList = List.Select(names, each Text.StartsWith(_, "dt.") or Text.StartsWith(_, "dt:")),
        timeList = List.Select(names, each Text.StartsWith(_, "t.") or Text.StartsWith(_, "t:")),
        logicalList = List.Select(names, each Text.StartsWith(_, "l.") or Text.StartsWith(_, "l:")),
        binaryList = List.Select(names, each Text.StartsWith(_, "b.") or Text.StartsWith(_, "b:")),
        floatList = List.Select(names, each Text.StartsWith(_, "f.") or Text.StartsWith(_, "f:")),
        integerList = List.Select(names, each Text.StartsWith(_, "n.") or Text.StartsWith(_, "n:"))
    in
        [text = textList, date = dateList, datetime = dateTimeList, time = timeList, logical = logicalList, binary = binaryList, float = floatList, integer = integerList];

setColumnNames = (indata as table) as table =>
    let
        columnNames = Table.ColumnNames(indata),
        newColumnNames = List.Transform(columnNames, each {_, Text.AfterDelimiter(_, ":")}),
        outdata = Table.RenameColumns(indata, newColumnNames)
    in
        outdata;

SetColumnData = (types as record, indata as table) as table =>
    let
        textTable = Table.TransformColumns(indata, List.Transform(types[text], each {_, each _, Text.Type})),
        dateTable = Table.TransformColumns(textTable, List.Transform(types[date], each {_, each Date.FromText(_), Date.Type})),
        dateTimeTable = Table.TransformColumns(dateTable, List.Transform(types[datetime], each {_, each DateTime.FromText(_), DateTime.Type})),
        timeTable = Table.TransformColumns(dateTimeTable, List.Transform(types[time], each {_, each Time.FromText(_), Time.Type})),
        logicalTable = Table.TransformColumns(timeTable, List.Transform(types[logical], each {_, each Logical.FromText(_), Logical.Type})),
        binaryTable = Table.TransformColumns(logicalTable, List.Transform(types[binary], each {_, each Binary.FromText(_), Binary.Type})),
        floatTable = Table.TransformColumns(binaryTable, List.Transform(types[float], each {_, each _,  Number.Type})),
        integerTable = Table.TransformColumns(floatTable, List.Transform(types[integer], each {_, each _,  Int64.Type})),
        finalTable = setColumnNames(integerTable)
    in
        finalTable;

GetData = (url as text, lds as text, authToken as text, id as text) as table =>
    let
        extractedData = ExtractData(url, lds, authToken, id),
        tableData = Table.FromRecords(extractedData),
        columnType = GetColumnDataType(tableData),
        data = SetColumnData(columnType, tableData)
    in
        data;

GetResults = (url as text, lds as text) as list =>
    let
        authToken = Login(url, Extension.CurrentCredential()[Username], Extension.CurrentCredential()[Password]),
        queryIds = SharedQueries(url, lds, authToken),
        ids = GetIds(queryIds),
        results = List.Generate(()=> [index = 0, y={ids[id]{0}, ids[id]{0}, GetData(url, lds, authToken, ids[id]{0}), "Table", "Table", true}], each [index]< List.Count(ids[id]), each [index=[index] + 1, y={ids[id]{index}, ids[id]{index}, GetData(url, lds, authToken, ids[id]{index}), "Table", "Table", true}], each [y])
    in
        results;
