inputFolder = @"D:\shared\3dModels\AImodels04\"
outputFolder = @"D:\shared\3dModels\AImodels06\"

fn ensureTrailingSlash folderPath =
(
    if folderPath == undefined or folderPath.count == 0 then ""
    else if folderPath[folderPath.count] == '\\' then folderPath
    else folderPath + "\\"
)

fn collectGeometryNodes =
(
    for node in geometry where isValidNode node collect node
)

fn previewGeometryNodes geometryNodes =
(
    if geometryNodes.count == 0 then return false

    select geometryNodes
    completeRedraw()
    try (max zoomext sel all) catch ()
    redrawViews()
    try (windows.processPostedMessages()) catch ()

    true
)

fn sanitizeTagValue rawValue =
(
    local cleanedValue = trimRight (trimLeft rawValue)
    cleanedValue = substituteString cleanedValue " " ""
    cleanedValue = substituteString cleanedValue "/" "-"
    cleanedValue = substituteString cleanedValue "\\" "-"
    cleanedValue = substituteString cleanedValue ":" "-"
    cleanedValue = substituteString cleanedValue "*" ""
    cleanedValue = substituteString cleanedValue "?" ""
    cleanedValue = substituteString cleanedValue "\"" ""
    cleanedValue = substituteString cleanedValue "<" ""
    cleanedValue = substituteString cleanedValue ">" ""
    cleanedValue = substituteString cleanedValue "|" ""
    cleanedValue
)

fn promptForMaterialAndSize fileNameOnly =
(
    dotNet.loadAssembly "System.Windows.Forms"
    dotNet.loadAssembly "System.Drawing"

    local form = dotNetObject "System.Windows.Forms.Form"
    local infoLabel = dotNetObject "System.Windows.Forms.Label"
    local materialLabel = dotNetObject "System.Windows.Forms.Label"
    local sizeLabel = dotNetObject "System.Windows.Forms.Label"
    local materialCombo = dotNetObject "System.Windows.Forms.ComboBox"
    local sizeCombo = dotNetObject "System.Windows.Forms.ComboBox"
    local okButton = dotNetObject "System.Windows.Forms.Button"
    local skipButton = dotNetObject "System.Windows.Forms.Button"
    local cancelButton = dotNetObject "System.Windows.Forms.Button"
    local dialogResultClass = dotNetClass "System.Windows.Forms.DialogResult"
    local comboStyleClass = dotNetClass "System.Windows.Forms.ComboBoxStyle"

    form.Text = "Assign FBX Material Tag"
    form.Width = 460
    form.Height = 235
    form.FormBorderStyle = (dotNetClass "System.Windows.Forms.FormBorderStyle").FixedDialog
    form.StartPosition = (dotNetClass "System.Windows.Forms.FormStartPosition").CenterScreen
    form.MaximizeBox = false
    form.MinimizeBox = false
    form.TopMost = true

    infoLabel.AutoSize = false
    infoLabel.Left = 12
    infoLabel.Top = 12
    infoLabel.Width = 420
    infoLabel.Height = 55
    infoLabel.Text = "Choose the material tag and texture size for:" + "\r\n\r\n" + fileNameOnly

    materialLabel.AutoSize = true
    materialLabel.Left = 12
    materialLabel.Top = 80
    materialLabel.Text = "Material"

    materialCombo.Left = 110
    materialCombo.Top = 76
    materialCombo.Width = 322
    materialCombo.DropDownStyle = comboStyleClass.DropDown
    materialCombo.Items.AddRange #("greyrock", "blackrock", "oldwood", "oldbroze", "mixed")
    materialCombo.Text = "greyrock"

    sizeLabel.AutoSize = true
    sizeLabel.Left = 12
    sizeLabel.Top = 115
    sizeLabel.Text = "Texture size"

    sizeCombo.Left = 110
    sizeCombo.Top = 111
    sizeCombo.Width = 322
    sizeCombo.DropDownStyle = comboStyleClass.DropDown
    sizeCombo.Items.AddRange #("512", "1k", "2k", "4k", "8k")
    sizeCombo.Text = "2k"

    okButton.Text = "OK"
    okButton.Left = 176
    okButton.Top = 150
    okButton.Width = 80
    okButton.DialogResult = dialogResultClass.OK

    skipButton.Text = "Skip"
    skipButton.Left = 264
    skipButton.Top = 150
    skipButton.Width = 80
    skipButton.DialogResult = dialogResultClass.Retry

    cancelButton.Text = "Cancel"
    cancelButton.Left = 352
    cancelButton.Top = 150
    cancelButton.Width = 80
    cancelButton.DialogResult = dialogResultClass.Cancel

    form.Controls.Add infoLabel
    form.Controls.Add materialLabel
    form.Controls.Add materialCombo
    form.Controls.Add sizeLabel
    form.Controls.Add sizeCombo
    form.Controls.Add okButton
    form.Controls.Add skipButton
    form.Controls.Add cancelButton
    form.AcceptButton = okButton
    form.CancelButton = cancelButton

    local responseResult = form.ShowDialog()
    local materialValue = sanitizeTagValue materialCombo.Text
    local sizeValue = sanitizeTagValue sizeCombo.Text

    if responseResult == dialogResultClass.Cancel then
    (
        #cancel
    )
    else if responseResult == dialogResultClass.Retry then
    (
        #skip
    )
    else
    (
        if materialValue == "" or sizeValue == "" then
        (
            messageBox "Please enter both a material tag and a texture size." title:"Missing Value"
            promptForMaterialAndSize fileNameOnly
        )
        else
        (
            #(materialValue, sizeValue)
        )
    )
)

fn buildTaggedMaterial materialTag =
(
    local taggedMaterial = PhysicalMaterial()
    taggedMaterial.name = materialTag
    taggedMaterial.base_color = color 180 180 180
    taggedMaterial.roughness = 0.75
    taggedMaterial
)

fn assignMaterialToGeometry geometryNodes taggedMaterial =
(
    for node in geometryNodes where isValidNode node do
    (
        node.material = taggedMaterial
    )
)

selectedInputFolder = getSavePath caption:"Select FBX Input Folder" initialDir:inputFolder

if selectedInputFolder == undefined then
(
    messageBox "No input folder selected." title:"Batch Cancelled"
)
else
(
    local selectedOutputFolder = getSavePath caption:"Select FBX Output Folder" initialDir:outputFolder

    if selectedOutputFolder == undefined then
    (
        messageBox "No output folder selected." title:"Batch Cancelled"
    )
    else
    (
        inputFolder = ensureTrailingSlash selectedInputFolder
        outputFolder = ensureTrailingSlash selectedOutputFolder

        if not doesDirectoryExist outputFolder do makeDir outputFolder

        local fbxFiles = getFiles (inputFolder + "*.fbx")
        local cancelBatch = false

        format "Found % FBX files.\n" fbxFiles.count

        for f in fbxFiles while not cancelBatch do
        (
            local fileNameOnly = getFilenameFile f
            format "\nProcessing: %\n" fileNameOnly

            resetMaxFile #noPrompt

            try (importFile f #noPrompt using:FBXIMP) catch
            (
                format "ERROR: Import failed for %.\n" fileNameOnly
                continue
            )

            local geometryNodes = collectGeometryNodes()

            if geometryNodes.count == 0 then
            (
                format "WARNING: No geometry found in %.\n" fileNameOnly
                continue
            )

            previewGeometryNodes geometryNodes

            local promptResult = promptForMaterialAndSize fileNameOnly

            if promptResult == #cancel then
            (
                cancelBatch = true
                format "Batch cancelled by user.\n"
            )
            else if promptResult == #skip then
            (
                format "Skipped: %\n" fileNameOnly
            )
            else
            (
                local materialTag = promptResult[1]
                local sizeTag = promptResult[2]
                local taggedMaterial = buildTaggedMaterial materialTag
                local outFile = outputFolder + fileNameOnly + "_" + materialTag + "_" + sizeTag + ".fbx"

                assignMaterialToGeometry geometryNodes taggedMaterial

                try
                (
                    exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
                    format "Exported tagged FBX: %\n" outFile
                )
                catch
                (
                    format "ERROR: Export failed for %.\n" fileNameOnly
                )
            )
        )

        messageBox "FBX material tagging batch complete." title:"Process Complete"
    )
)