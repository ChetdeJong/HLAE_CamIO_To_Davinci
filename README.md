# HLAE CamIO to Davinci Resolve Import script
Script to import camera data from HLAE .cam file to Fusion of Davinci Resolve.
Works the same as [similiar one for After Effects,](https://github.com/xNWP/HLAE-CamIO-To-AE) but with extra goodies.

# Usage
- Download latest release.
- Unzip and run install.bat, so it copies file to right folder.
 
In Davinci Resolve:
- Make sure the correct FPS of clip is set in clip attributes.
- Open Fusion page for that clip.
- Open script in Workspace > Scripts > HLAE.
- Select file and wait for import, **it may take some time.**
- After import it should open in Inspector text box with apply button. If it didn't open, then find it in MyImagePlane node, then open User tab.
- In text box paste output of `getpos` command from the game. You're supposed to go to place where you want tracked object to be and then execute that command in console.
- Hit apply and it should place black solid in desired place.

## Notes
- Only V2 (current version) of .cam file is supported.
- **Fusion may take a while to set keyframes, especially with high fps and long clips. There is no way to cancel it as program freezes while setting keyframes.** 
