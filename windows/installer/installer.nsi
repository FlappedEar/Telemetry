; NSIS installer for FlappedEar Telemetry (Windows 10/11, 64-bit).
;
; The install folder is fixed (no folder page), so the installer and the
; uninstaller may clear it entirely without touching anything of the user's.
;
; Built by the Release workflow:
;   makensis -DVERSION=0.3.0 -DSOURCE_DIR=<Release folder> -DOUTFILE=<setup.exe> installer.nsi
; It installs for the current user only (no administrator rights), adds a
; Start menu shortcut and an uninstaller. Saved days live in the user's app
; data, not in the install folder, so uninstalling never touches them.
; The installer is not code-signed, so SmartScreen warns on first start.

Unicode true
!include "MUI2.nsh"
!include "x64.nsh"

!ifndef VERSION
  !error "Pass /DVERSION=x.y.z"
!endif
!ifndef SOURCE_DIR
  !error "Pass /DSOURCE_DIR=<folder with telemetry.exe>"
!endif
!ifndef OUTFILE
  !define OUTFILE "FlappedEar-Telemetry-${VERSION}-windows-setup.exe"
!endif

!define APP_NAME "FlappedEar Telemetry"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\FlappedEarTelemetry"

Name "${APP_NAME}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP_NAME}"
RequestExecutionLevel user
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "FileDescription" "${APP_NAME} installer"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Apache License 2.0"

!define MUI_ICON "..\runner\resources\app_icon.ico"
!define MUI_UNICON "..\runner\resources\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\telemetry.exe"

!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Polish"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "${APP_NAME} needs 64-bit Windows."
    Abort
  ${EndIf}
FunctionEnd

Section "Install"
  ; Clear the previous version first so files a newer version no longer
  ; ships do not stay behind. The folder is ours alone.
  RMDir /r "$INSTDIR"
  SetOutPath "$INSTDIR"
  File /r "${SOURCE_DIR}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\${APP_NAME}.lnk" "$INSTDIR\telemetry.exe"

  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "FlappedEar"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\telemetry.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\${APP_NAME}.lnk"
  ; Fixed folder owned by this app; saved days are not kept in it.
  IfFileExists "$INSTDIR\telemetry.exe" 0 +2
    RMDir /r "$INSTDIR"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
SectionEnd
