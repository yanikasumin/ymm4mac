import Foundation

// GPU 処理系のカスタムシェーダ系エフェクトの定義層。
//
// いずれも処理器は暫定の素通し（`GPUEffectDefinitionBase` が返す
// `GPUEffectPassthroughProcessor`）であり、シェーダの実行はまだ
// 行われない。パラメータの型・既定値・範囲は本家定義クラスの
// 実測に基づく。

/// HLSL ピクセルシェーダ（コード）。本家 `HlslPixelShaderCodeEffect`。
/// パラメータ（実測）: InputExpand / OutputExpand は Animation
/// (既定 0, 0〜2000)、Value0〜Value3 は Animation(既定 0,
/// -100000〜100000)、Source は既定が本家の HLSL テンプレート文。
public final class HlslPixelShaderCodeEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HlslPixelShaderCodeEffect, YukkuriMovieMaker"
    }

    /// 本家の既定ソースコード（HLSL テンプレート）。
    public static let defaultSourceCode: String =
        "Texture2D InputTexture : register(t0);\r\n" +
        "SamplerState InputSampler : register(s0);\r\n" +
        "cbuffer constants : register(b0)\r\n" +
        "{\r\n" +
        "\tfloat time: packoffset(c0.x);\r\n" +
        "\tfloat duration: packoffset(c0.y);\r\n" +
        "\r\n" +
        "\tfloat value0 : packoffset(c0.z);\r\n" +
        "\tfloat value1 : packoffset(c0.w);\r\n" +
        "\tfloat value2 : packoffset(c1.x);\r\n" +
        "\tfloat value3 : packoffset(c1.y);\r\n" +
        "\r\n" +
        "\tfloat left : packoffset(c1.z);\r\n" +
        "\tfloat top : packoffset(c1.w);\r\n" +
        "\tfloat right : packoffset(c2.x);\r\n" +
        "\tfloat bottom : packoffset(c2.y);\r\n" +
        "}; \r\n" +
        "\r\n" +
        "float4 main(float4 pos : SV_POSITION, float4 posScene : SCENE_POSITION, float4 uv : TEXCOORD0) : SV_Target\r\n" +
        "{\r\n" +
        "\tfloat4 color = InputTexture.Sample(InputSampler, uv.xy);\r\n" +
        "\treturn color;\r\n" +
        "};"

    /// 入力の拡張量（px）。
    public var inputExpand = Animation(defaultValue: 0, minValue: 0, maxValue: 2000)
    /// 出力の拡張量（px）。
    public var outputExpand = Animation(defaultValue: 0, minValue: 0, maxValue: 2000)
    /// 任意パラメータ 0。
    public var value0 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 1。
    public var value1 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 2。
    public var value2 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 3。
    public var value3 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// HLSL ソースコード。
    public var source: String = HlslPixelShaderCodeEffectDefinition.defaultSourceCode

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&inputExpand)
        body(&outputExpand)
        body(&value0)
        body(&value1)
        body(&value2)
        body(&value3)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "InputExpand":
            CodecSupport.decodeAnimation(value, into: &inputExpand)
            return true
        case "OutputExpand":
            CodecSupport.decodeAnimation(value, into: &outputExpand)
            return true
        case "Value0":
            CodecSupport.decodeAnimation(value, into: &value0)
            return true
        case "Value1":
            CodecSupport.decodeAnimation(value, into: &value1)
            return true
        case "Value2":
            CodecSupport.decodeAnimation(value, into: &value2)
            return true
        case "Value3":
            CodecSupport.decodeAnimation(value, into: &value3)
            return true
        case "Source":
            source = CodecSupport.string(value, default: source)
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "InputExpand", value: CodecSupport.encodeAnimation(inputExpand)),
            (key: "OutputExpand", value: CodecSupport.encodeAnimation(outputExpand)),
            (key: "Value0", value: CodecSupport.encodeAnimation(value0)),
            (key: "Value1", value: CodecSupport.encodeAnimation(value1)),
            (key: "Value2", value: CodecSupport.encodeAnimation(value2)),
            (key: "Value3", value: CodecSupport.encodeAnimation(value3)),
            (key: "Source", value: .string(source)),
        ] + super.encodeKnownFields()
    }
}

/// HLSL ピクセルシェーダ（ファイル）。本家 `HlslPixelShaderFileEffect`。
/// パラメータ（実測）: InputExpand / OutputExpand は Animation
/// (既定 0, 0〜2000)、Value0〜Value3 は Animation(既定 0,
/// -100000〜100000)、File は既定 null。
public final class HlslPixelShaderFileEffectDefinition: GPUEffectDefinitionBase {
    public override class var typeName: String {
        "YukkuriMovieMaker.Project.Effects.HlslPixelShaderFileEffect, YukkuriMovieMaker"
    }

    /// 入力の拡張量（px）。
    public var inputExpand = Animation(defaultValue: 0, minValue: 0, maxValue: 2000)
    /// 出力の拡張量（px）。
    public var outputExpand = Animation(defaultValue: 0, minValue: 0, maxValue: 2000)
    /// 任意パラメータ 0。
    public var value0 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 1。
    public var value1 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 2。
    public var value2 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// 任意パラメータ 3。
    public var value3 = Animation(defaultValue: 0, minValue: -100000, maxValue: 100000)
    /// HLSL ファイルのパス（未指定は nil）。
    public var file: String?

    public override func forEachAnimation(_ body: (inout Animation) -> Void) {
        body(&inputExpand)
        body(&outputExpand)
        body(&value0)
        body(&value1)
        body(&value2)
        body(&value3)
    }

    public override func decodeKnownField(_ key: String, _ value: JSONValue) -> Bool {
        switch key {
        case "InputExpand":
            CodecSupport.decodeAnimation(value, into: &inputExpand)
            return true
        case "OutputExpand":
            CodecSupport.decodeAnimation(value, into: &outputExpand)
            return true
        case "Value0":
            CodecSupport.decodeAnimation(value, into: &value0)
            return true
        case "Value1":
            CodecSupport.decodeAnimation(value, into: &value1)
            return true
        case "Value2":
            CodecSupport.decodeAnimation(value, into: &value2)
            return true
        case "Value3":
            CodecSupport.decodeAnimation(value, into: &value3)
            return true
        case "File":
            file = value.stringValue
            return true
        default:
            return super.decodeKnownField(key, value)
        }
    }

    public override func encodeKnownFields() -> [(key: String, value: JSONValue)] {
        [
            (key: "InputExpand", value: CodecSupport.encodeAnimation(inputExpand)),
            (key: "OutputExpand", value: CodecSupport.encodeAnimation(outputExpand)),
            (key: "Value0", value: CodecSupport.encodeAnimation(value0)),
            (key: "Value1", value: CodecSupport.encodeAnimation(value1)),
            (key: "Value2", value: CodecSupport.encodeAnimation(value2)),
            (key: "Value3", value: CodecSupport.encodeAnimation(value3)),
            (key: "File", value: file.map(JSONValue.string) ?? .null),
        ] + super.encodeKnownFields()
    }
}
