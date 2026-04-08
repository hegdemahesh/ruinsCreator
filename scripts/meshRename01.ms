-- Define input and output folders
inputFolder  = @"C:\DB\3dModels\AIMOdelsNew\"   -- change to your source folder
outputFolder = @"C:\DB\3dModels\AImodels02\"  -- change to your destination folder

-- Get list of FBX files in input folder
fbxFiles = getFiles (inputFolder + "*.fbx")

for f in fbxFiles do
(
    -- Extract filename without extension
    fileNameOnly = getFilenameFile f
    
    -- Reset scene before import
    resetMaxFile #noPrompt
    
    -- Import FBX
    importFile f #noPrompt using:FBXIMP
    
    -- Rename all geometry objects to match file name
    for obj in geometry do
    (
        obj.name = fileNameOnly
    )
    
    -- Build output path
    outFile = outputFolder + fileNameOnly + ".fbx"
    
    -- Export corrected FBX
    exportFile outFile #noPrompt selectedOnly:false using:FBXEXP
)

messageBox "FBX batch rename and export complete!" title:"Process Done"