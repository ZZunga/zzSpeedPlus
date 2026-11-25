import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// zzSpeedPlus
//  - 10필드 칸(반폭): 위쪽 줄 = 속도계 아이콘 + 보조 값 + 단위 / 아래쪽 줄 = 현재 속도 + 단위
//  - 넓은 칸(전체폭): 위쪽 = 아이콘 + "zzSpeedPlus" + 모드/단위 표시 / 아래 = 두 값 같은 크기로 나란히
//    · 높이가 낮아 타이틀이 안 들어가면 타이틀을 빼고 C10Main 폰트로 숫자만 그림
//    · 높이가 큰 넓은 칸은 같은 배치에서 숫자 줄만 가운데 정렬
// 배터리: 판단·좌표·폰트는 onLayout에서 한 번, compute는 값이 바뀔 때만 문자열 생성, onUpdate는 그리기만.
typedef Font as WatchUi.FontResource or Graphics.FontDefinition;

class zzSpeedPlusView extends WatchUi.DataField {

    enum { MODE_SPEED, MODE_AVG, MODE_BREVET, MODE_LAP, MODE_MAX }
    private const MODE_LABELS = ["", "AVG", "BRV", "LAP", "MAX"];

    // ---- 설정 ----
    private var _mode as Number = MODE_AVG;
    private var _factor as Float = 360.0f;       // m/s → (km/h ×100) / (mi/h ×100 = 223.69)
    private var _u1 as String = "km";
    private var _u2 as String = "/h";
    private var _label as String = "";           // 넓은 칸 오른쪽 위 표시 ("AVG  km/h")
    // 속도 색상 (zzSpeed 와 같은 설정 값 colorHigh/colorLow, 배포 후 순서 변경 금지). 0 = 기본 글자색
    //  [야간(검정 배경), 주간(흰 배경)]
    private const COLORS_NIGHT = [0, Graphics.COLOR_RED, Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW, Graphics.COLOR_YELLOW,
        Graphics.COLOR_GREEN, Graphics.COLOR_BLUE, Graphics.COLOR_PURPLE, Graphics.COLOR_PINK, Graphics.COLOR_PINK, Graphics.COLOR_LT_GRAY];
    private const COLORS_DAY   = [0, Graphics.COLOR_DK_RED, Graphics.COLOR_ORANGE, Graphics.COLOR_YELLOW, Graphics.COLOR_ORANGE,
        Graphics.COLOR_DK_GREEN, Graphics.COLOR_DK_BLUE, Graphics.COLOR_PURPLE, Graphics.COLOR_PINK, Graphics.COLOR_DK_RED, Graphics.COLOR_DK_GRAY];
    private var _dayFast as Number = 0, _daySlow as Number = 0;       // 주간(흰 배경)
    private var _nightFast as Number = 0, _nightSlow as Number = 0;   // 야간(검정 배경)
    private var _colorOn as Boolean = true;
    private var _thr as Number = 5;              // 색 바뀌는 기준 (%)
    private var _two as Boolean = false;         // 소수 둘째자리 (10필드 칸은 단위 숨김)
    enum { SPEED_NORMAL, SPEED_FAST, SPEED_SLOW }
    // 배경색 : 0 기기 화면색에 맞춤 (1050/1060 은 #17181D / 남색 글씨)
    //          1 기기가 알려준 검정·흰색 그대로 (기본, 지금까지의 동작)
    //          2 투명 - 배경을 칠하지 않아 기기 배경이 그대로 비친다
    enum { BG_AUTO, BG_PLAIN, BG_CLEAR }
    private var _bgMode as Number = BG_PLAIN;
    private var _speedState as Number = SPEED_NORMAL;

    // ---- 레이아웃 ----
    private var _wide as Boolean = false;
    private var _titleOn as Boolean = true;
    private var _L as Number = 0, _T as Number = 0, _R as Number = 0, _B as Number = 0;

    // 10필드 칸
    // 폰트: null 대신 시스템 폰트로 초기화(해제 시에도 시스템 폰트로 되돌림) → 타입 체크 통과
    private var _fMain as Font = Graphics.FONT_XTINY, _fMainDec as Font = Graphics.FONT_XTINY;
    private var _fSub as Font = Graphics.FONT_XTINY, _fSubDec as Font = Graphics.FONT_XTINY;
    private var _fUnitMain as Font = Graphics.FONT_XTINY, _fUnitSub as Font = Graphics.FONT_XTINY;
    private var _c10Loaded as Boolean = false;
    private var _yMain as Number = 0, _yMainDec as Number = 0, _yUnitMain2 as Number = 0;
    private var _ySubDec as Number = 0, _yUnitSub2 as Number = 0;
    // 설정(소수 둘째자리)이 바뀌어도 onLayout 없이 바로 맞도록 두 경우 모두 미리 계산
    private var _xMainValU as Number = 0, _xSubValU as Number = 0;
    private var _wMainDec1 as Number = 0, _wMainDec2 as Number = 0, _wSubDec1 as Number = 0, _wSubDec2 as Number = 0;

    // 넓은 칸
    private var _fVal as Font = Graphics.FONT_XTINY, _fTitle as Font = Graphics.FONT_XTINY, _fLabel as Font = Graphics.FONT_XTINY;
    private var _xTitleText as Number = 0, _yLabel as Number = 0;
    private var _yVal as Number = 0, _xc1 as Number = 0, _xc2 as Number = 0, _xcMid as Number = 0;
    private var _yDiv1 as Number = 0;

    // ---- 값 캐시 (×100 정수, -1 = 없음, -2 = 다시 만들기) ----
    private var _main10 as Number = -2, _sub10 as Number = -2;
    private var _mainI as String = "--", _mainD as String = "", _mainS as String = "--";
    private var _subI as String = "--",  _subD as String = "",  _subS as String = "--";

    // ---- Lap ----
    private var _lapDist as Float = 0.0f, _lapTime as Number = 0;

    function initialize() {
        DataField.initialize();
        readSettings();
    }

    // App.onSettingsChanged()에서 호출 → WatchUi.requestUpdate()
    function readSettings() as Void {
        // dataMode (zzSpeed 와 같은 값): 0 이동평균, 1 절대평균(브레베), 2 최대, 3 랩, 4 없음
        // 배경색 : 0 기기 화면색에 맞춤, 1 검정·흰색 그대로(기본), 2 투명
        var bm = Application.Properties.getValue("bgMode");
        _bgMode = (bm instanceof Number && bm >= 0 && bm <= 2) ? bm as Number : BG_PLAIN;

        var m = Application.Properties.getValue("dataMode");
        var MAP = [MODE_AVG, MODE_BREVET, MODE_MAX, MODE_LAP, MODE_SPEED];
        _mode = (m instanceof Number && m >= 0 && m <= 4) ? MAP[m] as Number : MODE_BREVET;
        var t = Application.Properties.getValue("showTwoDecimal");
        _two = (t instanceof Boolean) ? t : false;
        var th = Application.Properties.getValue("threshold");
        _thr = (th instanceof Number && th >= 0 && th <= 100) ? th : 5;
        var metric = System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
        _factor = metric ? 360.0f : 223.69363f;
        _u1 = metric ? "km" : "mi";
        var hi = colorIdx(Application.Properties.getValue("colorHigh"), 9);
        var lo = colorIdx(Application.Properties.getValue("colorLow"), 5);
        _nightFast = COLORS_NIGHT[hi] as Number; _dayFast = COLORS_DAY[hi] as Number;
        _nightSlow = COLORS_NIGHT[lo] as Number; _daySlow = COLORS_DAY[lo] as Number;
        _colorOn = (_dayFast != 0 || _daySlow != 0 || _nightFast != 0 || _nightSlow != 0);
        _speedState = SPEED_NORMAL;
        _label = (_mode == MODE_SPEED) ? (_u1 + _u2) : (MODE_LABELS[_mode] + "  " + _u1 + _u2);
        _main10 = -2; _sub10 = -2;
    }

    private function colorIdx(v as Application.Properties.ValueType or Null, def as Number) as Number {
        return (v instanceof Number && v >= 0 && v < COLORS_NIGHT.size()) ? v : def;
    }

    // =========================================================
    // 레이아웃
    // =========================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        _wide = w > System.getDeviceSettings().screenWidth * 0.75f;
        _L = (w * 0.05f + 0.5f).toNumber();
        _T = (h * 0.05f + 0.5f).toNumber();
        _R = w - _L;
        _B = h - _T;
        if (_wide) { layoutWide(dc, w, h); } else { layoutCell10(dc, w); }
    }

    private function layoutCell10(dc as Graphics.Dc, w as Number) as Void {
        _fVal = Graphics.FONT_XTINY; _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
        loadCell10Fonts();
        var ug = (w * 0.02f).toNumber(); if (ug < 2) { ug = 2; }

        var aMain = Graphics.getFontAscent(_fMain);
        _yMain      = _B - aMain;
        _yMainDec   = _yMain + aMain - Graphics.getFontAscent(_fMainDec);
        // 2단 단위: 위 줄은 숫자 윗선, 아래 줄은 위 줄 바로 아래 (p 꼬리 + 약간 띄움). 숫자 바닥선은 넘지 않음
        var aUnit = Graphics.getFontAscent(_fUnitMain);
        _yUnitMain2 = _yMain + (aUnit * 1.45f + 0.5f).toNumber();
        if (_yUnitMain2 > _B - aUnit) { _yUnitMain2 = _B - aUnit; }
        _xMainValU  = _R - unitWidth(dc, _fUnitMain) - ug;
        _wMainDec1  = dc.getTextWidthInPixels(".0", _fMainDec);
        _wMainDec2  = dc.getTextWidthInPixels(".00", _fMainDec);

        var aSub = Graphics.getFontAscent(_fSub);
        _ySubDec   = _T + aSub - Graphics.getFontAscent(_fSubDec);
        _yUnitSub2 = _T + aSub - Graphics.getFontAscent(_fUnitSub);
        _xSubValU  = _R - unitWidth(dc, _fUnitSub) - ug;
        _wSubDec1  = dc.getTextWidthInPixels(".0", _fSubDec);
        _wSubDec2  = dc.getTextWidthInPixels(".00", _fSubDec);
    }

    private function loadCell10Fonts() as Void {
        if (!_c10Loaded) {
            _fMain     = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource;
            _fMainDec  = WatchUi.loadResource(Rez.Fonts.C10MainDec) as WatchUi.FontResource;
            _fSub      = WatchUi.loadResource(Rez.Fonts.C10Sub) as WatchUi.FontResource;
            _fSubDec   = WatchUi.loadResource(Rez.Fonts.C10SubDec) as WatchUi.FontResource;
            _fUnitMain = WatchUi.loadResource(Rez.Fonts.C10UnitMain) as WatchUi.FontResource;
            _fUnitSub  = WatchUi.loadResource(Rez.Fonts.C10UnitSub) as WatchUi.FontResource;
            _c10Loaded = true;
        }
    }

    private function layoutWide(dc as Graphics.Dc, w as Number, h as Number) as Void {
        // 10필드 폰트는 해제 (낮은 칸 fallback에서만 C10Main을 다시 씀)
        _fMainDec = Graphics.FONT_XTINY; _fSub = Graphics.FONT_XTINY; _fSubDec = Graphics.FONT_XTINY;
        _fUnitMain = Graphics.FONT_XTINY; _fUnitSub = Graphics.FONT_XTINY;
        _c10Loaded = false;
        _fTitle = WatchUi.loadResource(Rez.Fonts.WideTitle) as WatchUi.FontResource;
        _fLabel = WatchUi.loadResource(Rez.Fonts.WideLabel) as WatchUi.FontResource;
        var fv  = WatchUi.loadResource(Rez.Fonts.WideVal) as WatchUi.FontResource;

        var gap = (w * 0.04f).toNumber(); if (gap < 4) { gap = 4; }
        var vg  = (h * 0.05f).toNumber(); if (vg < 2) { vg = 2; }
        var aTitle = Graphics.getFontAscent(_fTitle);
        var hTitle = Graphics.getFontHeight(_fTitle);   // 'p' 아래 꼬리까지 포함
        var hu = _B - _T;

        _titleOn = (hu - hTitle - vg) >= Graphics.getFontAscent(fv);
        if (_titleOn) {
            _fVal = fv; _fMain = Graphics.FONT_XTINY;
        } else {
            // 낮은 칸 (예: 550/850의 420×60): 타이틀 빼고 숫자만
            _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
            if (Graphics.getFontAscent(fv) <= hu) { _fVal = fv; _fMain = Graphics.FONT_XTINY; }
            else { _fMain = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource; _fVal = _fMain; }
        }

        var top = _T;
        if (_titleOn) {
            _xTitleText = _L + dc.getTextWidthInPixels("@", _fTitle);
            _yLabel = _T + aTitle - Graphics.getFontAscent(_fLabel);
            top = _T + hTitle + vg;
        }
        var aVal = Graphics.getFontAscent(_fVal);
        _yVal  = top + (_B - top - aVal) / 2;          // 남는 세로 공간의 가운데
        _yDiv1 = top;
        var mid = w / 2;
        _xc1   = (_L + mid - gap / 2) / 2;
        _xc2   = (mid + gap / 2 + _R) / 2;
        _xcMid = mid;
    }

    private function unitWidth(dc as Graphics.Dc, f as Font) as Number {
        var a = dc.getTextWidthInPixels(_u1, f), c = dc.getTextWidthInPixels(_u2, f);
        return (a > c) ? a : c;
    }

    // =========================================================
    // 계산
    // =========================================================
    function onTimerLap() as Void {
        var info = Activity.getActivityInfo();
        if (info != null) {
            var d = info.elapsedDistance, t = info.timerTime;
            _lapDist = (d != null) ? d : 0.0f;
            _lapTime = (t != null) ? t : 0;
        }
    }

    function onTimerReset() as Void { _lapDist = 0.0f; _lapTime = 0; }

    function compute(info as Activity.Info) as Void {
        var v = toV10(info.currentSpeed);
        if (v != _main10) {
            _main10 = v;
            var s = split(v); _mainI = s[0]; _mainD = s[1]; _mainS = _mainI + _mainD;
        }
        var mps = null as Float?;
        if (_mode == MODE_AVG) {
            mps = info.averageSpeed;                               // 정지시간 제외
        } else if (_mode == MODE_MAX) {
            mps = info.maxSpeed;
        } else if (_mode == MODE_BREVET || _mode == MODE_LAP) {
            var d = info.elapsedDistance;
            if (_mode == MODE_BREVET) {                            // 정지시간 포함
                var t = info.elapsedTime;
                if (d != null && t != null && t > 0) { mps = d * 1000.0f / t; }
            } else {                                               // Lap
                var t = info.timerTime;
                if (d != null && t != null) {
                    var dt = t - _lapTime;
                    if (dt > 0) { mps = (d - _lapDist) * 1000.0f / dt; }
                }
            }
        }
        if (_mode != MODE_SPEED) {
            v = toV10(mps);
            if (v != _sub10) {
                _sub10 = v;
                var s = split(v); _subI = s[0]; _subD = s[1]; _subS = _subI + _subD;
            }
        }

        // 속도 색상: 기준값 대비 ±threshold% 초과일 때만 (정수 비교, 실수 연산 없음)
        if (_colorOn) {
            var ref10 = (_mode == MODE_AVG || _mode == MODE_BREVET || _mode == MODE_LAP)
                        ? _sub10 : toV10(info.averageSpeed);
            var m10 = _main10;
            if (ref10 <= 0 || m10 < 0)          { _speedState = SPEED_NORMAL; }
            else if (m10 * 100 > ref10 * (100 + _thr)) { _speedState = SPEED_FAST; }
            else if (m10 * 100 < ref10 * (100 - _thr)) { _speedState = SPEED_SLOW; }
            else                                { _speedState = SPEED_NORMAL; }
        }
    }

    private function toV10(mps as Float?) as Number {
        return (mps == null) ? -1 : (mps * _factor + 0.5f).toNumber();
    }

    // v100 = 속도 ×100. 100 이상이면 소수부 생략, 둘째자리 설정이면 .00
    private function split(v100 as Number) as Array<String> {
        if (v100 < 0)      { return ["--", ""]; }
        if (_two) {
            var r = v100;
            if (r >= 10000) { return [(r / 100).toString(), ""]; }
            return [(r / 100).toString(), "." + (r % 100).format("%02d")];
        }
        var v10 = (v100 + 5) / 10;
        if (v10 >= 1000) { return [(v10 / 10).toString(), ""]; }
        return [(v10 / 10).toString(), "." + (v10 % 10)];
    }

    // =========================================================
    // 그리기
    // =========================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        var sys = getBackgroundColor();
        var sysClear = (sys == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        var night = (sys == Graphics.COLOR_BLACK || sysClear);
        var soft = (_bgMode == BG_AUTO)
                && (System.getDeviceSettings().screenWidth >= 480);   // 1050 / 1060
        var fg = night ? Graphics.COLOR_WHITE
                       : (soft ? 0x313152 : Graphics.COLOR_BLACK);
        var bg = night ? (soft ? 0x17181D : Graphics.COLOR_BLACK)
                       : (soft ? 0xDCDCDC : Graphics.COLOR_WHITE);   // 밝은 배경도 순백이 아니다
        // 투명 : 아예 칠하지 않아 기기 배경이 그대로 비친다 (테마가 무엇이든 일치)
        if (_bgMode == BG_CLEAR || (_bgMode == BG_AUTO && sysClear)) {
            bg = Graphics.COLOR_TRANSPARENT;
        }
        dc.setColor(fg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        var mc = 0;
        if (_speedState == SPEED_FAST)      { mc = night ? _nightFast : _dayFast; }
        else if (_speedState == SPEED_SLOW) { mc = night ? _nightSlow : _daySlow; }
        if (mc == 0) { mc = fg; }
        if (_wide) { drawWide(dc, fg, mc); } else { drawCell10(dc, fg, mc); }
    }

    private function drawCell10(dc as Graphics.Dc, fg as Number, mc as Number) as Void {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_L, _T, _fSub, "@", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(mc, Graphics.COLOR_TRANSPARENT);

        var x = _two ? _R : _xMainValU;
        if (_mainD.length() > 0) {
            dc.drawText(x, _yMainDec, _fMainDec, _mainD, Graphics.TEXT_JUSTIFY_RIGHT);
            x -= _two ? _wMainDec2 : _wMainDec1;
        }
        dc.drawText(x, _yMain, _fMain, _mainI, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        if (!_two) {
            dc.drawText(_R, _yMain,      _fUnitMain, _u1, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(_R, _yUnitMain2, _fUnitMain, _u2, Graphics.TEXT_JUSTIFY_RIGHT);
        }

        if (_mode == MODE_SPEED) { return; }

        x = _two ? _R : _xSubValU;
        if (_subD.length() > 0) {
            dc.drawText(x, _ySubDec, _fSubDec, _subD, Graphics.TEXT_JUSTIFY_RIGHT);
            x -= _two ? _wSubDec2 : _wSubDec1;
        }
        dc.drawText(x, _T, _fSub, _subI, Graphics.TEXT_JUSTIFY_RIGHT);
        if (!_two) {
            dc.drawText(_R, _T,         _fUnitSub, _u1, Graphics.TEXT_JUSTIFY_RIGHT);
            dc.drawText(_R, _yUnitSub2, _fUnitSub, _u2, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    private function drawWide(dc as Graphics.Dc, fg as Number, mc as Number) as Void {
        if (_titleOn) {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_L, _T, _fTitle, "@", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_xTitleText, _T, _fTitle, "zzSpeedPlus", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _yLabel, _fLabel, _label, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.setColor(mc, Graphics.COLOR_TRANSPARENT);
        if (_mode == MODE_SPEED) {
            dc.drawText(_xcMid, _yVal, _fVal, _mainS, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(_xc1, _yVal, _fVal, _mainS, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_xc2, _yVal, _fVal, _subS,  Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_xcMid, _yDiv1, _xcMid, _B);
    }
}
