section Monday;

[DataSource.Kind = "MondayBoardConnector", Publish = "MondayBoardConnector.Publish"]
shared Monday = (Board_ID as text,Access_Token as text) =>
let
    // Step 1: Define Parameters
    Board = Board_ID,  // This is now required and cannot be null
    Key = Access_Token,  // This is now required and cannot be null
    

// Step 2: Function to get a page of data
    GetPage = (currentCursor as nullable text) =>
        let
            QueryText = if currentCursor = null then
                "{""query"": ""query { boards(ids: " & Board & ") { items_page(limit: 500) { cursor items { id, name, updated_at, group { title }, column_values { column { title }, text, ...on DependencyValue { display_value }, ...on MirrorValue { display_value }, ...on BoardRelationValue { display_value } } } } } }""}"
            else
                "{""query"": ""query { next_items_page(limit: 500, cursor: \""" & currentCursor & "\"" ) { cursor items { id, name, updated_at, group { title }, column_values { column { title }, text, ...on DependencyValue { display_value }, ...on MirrorValue { display_value }, ...on BoardRelationValue { display_value } } } } }""}",

            Source = Web.Contents(
                "https://api.monday.com/v2",
                [
                    Headers = [
                        #"Method" = "POST",
                        #"Content-Type" = "application/json",
                        #"Authorization" = "Bearer " & Key,
                        #"API-Version" = "2024-01"
                    ],
                    Content = Text.ToBinary(QueryText)
                ]
            ),
            JsonResponse = Json.Document(Source),
            PageData = if currentCursor = null then
                JsonResponse[data][boards]{0}[items_page]
            else
                JsonResponse[data][next_items_page]
        in
            PageData,

    // Step 3: Generate list of all pages using List.Generate with counter
    AllPages = List.Generate(
        () => [
            Page = GetPage(null),
            Items = Page[items],
            Cursor = Page[cursor],
            Counter = 0  // Initialize counter to 0
        ],
        each [Counter] = 0, 
        each [
            Page = GetPage([Cursor]),
            Items = Page[items],
            Cursor = Page[cursor],
            Counter = if [Cursor] = null then [Counter] + 1 else [Counter]  // Increment counter when cursor is null
        ],
        each [Items]
    ),

    // Step 4: Convert all items to a single list
    AllItems = List.Combine(AllPages),

    // Step 5: Transform items into records with dynamic columns
    ResultTable = Table.FromRecords(
        List.Transform(
            AllItems,
            each List.Accumulate(
                [column_values],
                [
                    ID = [id],
                    Title = [name],
                    UpdateDate = [updated_at],
                    Group = try [group][title] otherwise null
                ],
                (state, current) => Record.AddField(
                    state,
                    current[column][title],
                    if Record.HasFields(current, "display_value") then
                        current[display_value] ?? current[text]
                    else
                        current[text]
                )
            )
        )
    ),

    // Step 6: Clean up the base columns
    CleanedColumns = Table.TransformColumns(
        ResultTable,
        {
            {"ID", each Text.From(_), type text},
            {"UpdateDate", each DateTime.From(_), type datetime},
            {"Group", each if _ = null then "" else _, type text}
        }
    )
in
    CleanedColumns
;

MondayBoardConnector = [
    TestConnection = (dataSourcePath) => {"MondayBoardConnector.Contents"},
    Authentication = [
        Anonymous = []
    ]
];

MondayBoardConnector.Publish = [
    Beta = false,
    ButtonText = {"Monday.com | Board Connector", "Select this option to connect to your Monday.com board data."},
    SourceImage = MondayBoardConnector.Icons,
    SourceTypeImage = MondayBoardConnector.Icons
];

MondayBoardConnector.Icons = [
    Icon16 = {
        Extension.Contents("Monday16.png"),
        Extension.Contents("Monday20.png"),
        Extension.Contents("Monday24.png"),
        Extension.Contents("Monday32.png")
    },
    Icon32 = {
        Extension.Contents("Monday32.png"),
        Extension.Contents("Monday40.png"),
        Extension.Contents("Monday48.png"),
        Extension.Contents("Monday64.png")
    }
];