import Foundation

/// アニメーションの値1つ。本家 `AnimationValue` に対応し、double の値を1つ持つ。
public struct AnimationValue: Equatable, Sendable {
    public var value: Double

    public init(_ value: Double) {
        self.value = value
    }
}

/// 1つの数値プロパティの時間変化。
///
/// 本家 `Animation` の仕様を再現する。保持するデータは `values`（値の列）、
/// `animationType`、`span`、`bezier` と、プロパティごとに固定される定義値
/// （`defaultValue` / `minValue` / `maxValue` / `loop`、本家では保存対象外）。
/// 評価用の文脈（キーフレーム・アイテムの長さ・基準 FPS）は所有アイテムから
/// `setKeyFrames` / `setAnimationParameters` で注入される。
///
/// 評価は本家 `GetValue` の分岐を全て実装する。数式の正本は解析側
/// `ANIMATION-FORMULAS.md`。唯一の未確定事項は、ランダム移動のシード材料
/// である本家 `GetHashCode()` の具体値との対応付けであり、`randomSeed`
/// の説明を参照すること。
public struct Animation: Equatable, Sendable {
    /// 値の列。評価に使うのは先頭 `activeValueCount` 個（`activeValues`）。
    public var values: [AnimationValue]
    /// 補間・イージングの種類。
    public var animationType: AnimationType
    /// ランダム移動・反復移動の周期（秒）。
    public var span: Double
    /// ベジェ補間用。
    public var bezier: BezierAnimation

    /// 既定値（定義値。プロパティごとにコンストラクタで固定される）。
    public let defaultValue: Double
    /// 最小値（定義値）。
    public let minValue: Double
    /// 最大値（定義値）。
    public let maxValue: Double
    /// 繰り返し単位（定義値。0 で無効）。評価の最終処理で剰余を取る。
    public let loop: Double

    /// 評価用に注入されたキーフレーム（所有アイテムと共有されるものの写し）。
    public private(set) var keyFrames: KeyFrames
    /// 評価用に注入されたアイテムの長さ（フレーム）。
    public private(set) var length: Int
    /// キーフレーム位置の基準 FPS（所有アイテムへ伝播した FPS）。
    public private(set) var videoFPS: Int

    /// ランダム移動のシード材料。
    ///
    /// 本家では `Animation` オブジェクト自身の `GetHashCode()` を
    /// `StatelessRandom` のキーに使う。その具体値は .NET ランタイムの
    /// オブジェクトハッシュ実装に依存し、本家と同一の乱数列を再現する
    /// ための対応付けは未確定である。Swift では再現可能な明示値で代用し、
    /// 同一シード・同一フレームでは決定的に同じ値になることだけを保証する。
    public var randomSeed: Int64

    public init(
        defaultValue: Double,
        minValue: Double,
        maxValue: Double,
        loop: Double = 0,
        animationType: AnimationType = .none,
        values: [AnimationValue]? = nil,
        span: Double = 0,
        bezier: BezierAnimation = BezierAnimation(),
        keyFrames: KeyFrames = KeyFrames(),
        length: Int = 1,
        videoFPS: Int = 30,
        randomSeed: Int64 = 0
    ) {
        self.defaultValue = defaultValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.loop = loop
        self.animationType = animationType
        self.values = values ?? [AnimationValue(defaultValue)]
        self.span = span
        self.bezier = bezier
        self.keyFrames = keyFrames
        self.length = length
        self.videoFPS = videoFPS
        self.randomSeed = randomSeed
    }

    // MARK: - 評価用文脈の注入（本家 SetKeyFrames / SetAnimationParameters）

    public mutating func setKeyFrames(_ keyFrames: KeyFrames) {
        self.keyFrames = keyFrames
    }

    public mutating func setAnimationParameters(length: Int, videoFPS: Int) {
        self.length = length
        self.videoFPS = videoFPS
    }

    // MARK: - 有効な値の数

    /// 評価に使う値の個数。型によって決まる。
    ///
    /// - なし: 1個（定数値）
    /// - 移動量指定: 2個（開始値、1フレームあたりの移動量）
    /// - キーフレーム非対応の補間型（ランダム移動・反復移動）: 2個（開始値、終了値）
    /// - キーフレーム対応型: キーフレーム数 + 2個（開始値、各キーフレームでの値、終了値）
    public var activeValueCount: Int {
        switch animationType {
        case .none:
            return 1
        case .movementAmount, .random, .repetitive:
            return 2
        default:
            return keyFrames.frames.count + 2
        }
    }

    /// 評価に使う値。不足分は `defaultValue` で補う（防御的な措置であり、
    /// 正常な編集フローでは編集終了時の切り詰め・補充で常に揃っている）。
    private var resolvedActiveValues: [Double] {
        var result = values.prefix(activeValueCount).map(\.value)
        while result.count < activeValueCount {
            result.append(defaultValue)
        }
        return result
    }

    /// 先頭の値（本家 `GetFirstValue` 相当）。
    public var firstValue: Double {
        values.first?.value ?? defaultValue
    }

    // MARK: - 値の評価（本家 GetValue(frame, totalFrame, fps)）

    /// 指定フレームでの値を評価する。本家 `GetValue(frame, totalFrame, fps)`。
    ///
    /// 分岐構造は本家そのままで、キーフレーム系の4経路（補間移動系、
    /// _Int イージング系と Interpolation_Bezier、Linear_Bezier、その他の
    /// キーフレーム対応型）は本家では早期 return であり、最終処理
    /// （Loop の剰余と [minValue, maxValue] へのクランプ）を通らない。
    /// 最終処理を通るのは、なし・移動量指定・ランダム移動・反復移動と、
    /// キーフレーム非対応型の残余経路だけである。
    ///
    /// - Parameters:
    ///   - frame: アイテム内相対フレーム（評価 FPS の尺度）。
    ///   - totalFrame: アイテムの長さ（評価 FPS の尺度）。
    ///   - fps: 評価 FPS。キーフレーム位置は `位置 * fps / videoFPS` の整数演算で
    ///     この尺度へ換算してから区間を求める。
    public func value(atFrame frame: Int, length totalFrame: Int, fps: Int) -> Double {
        let rate = Double(frame) / Double(totalFrame)

        switch animationType {
        case .none:
            return applyingFinalProcessing(to: values.first?.value ?? defaultValue)

        case .movementAmount:
            // 開始値 + 移動量 × 率 × 総フレーム
            let from = values.first?.value ?? defaultValue
            let amount = values.dropFirst().first?.value ?? 0
            return applyingFinalProcessing(to: from + amount * rate * Double(totalFrame))

        case .random where span == 0:
            let from = values.first?.value ?? defaultValue
            let to = values.dropFirst().first?.value ?? defaultValue
            let random = StatelessRandom.getDouble(keys: [randomSeed, Int64(frame)])
            return applyingFinalProcessing(to: from + (to - from) * random)

        case .random:
            // Span > 0: Span 周期で乱数列をスプライン平滑化する
            let from = values.first?.value ?? defaultValue
            let to = values.dropFirst().first?.value ?? defaultValue
            let currentFrame = Int((Double(totalFrame) * rate).rounded(.awayFromZero))
            let randomRate = Self.randomMoveRate(
                seed: randomSeed, id: 0, frame: currentFrame, fps: fps, span: span
            )
            return applyingFinalProcessing(to: from + (to - from) * randomRate)

        case .repetitive where span == 0:
            // 本家は (int)(rate * totalFrame) が奇数のとき開始値、偶数のとき
            // 終了値を返す（直観とは逆の対応）
            let from = values.first?.value ?? defaultValue
            let to = values.dropFirst().first?.value ?? defaultValue
            let frameIndex = Int(rate * Double(totalFrame))
            return applyingFinalProcessing(to: frameIndex % 2 == 1 ? from : to)

        case .repetitive:
            // Span > 0: Span/2 を半周期とする三角波に Sine InOut を適用する
            let from = values.first?.value ?? defaultValue
            let to = values.dropFirst().first?.value ?? defaultValue
            let sec = (Double(totalFrame) * rate).rounded(.awayFromZero) / Double(fps)
            let repeatRate = Self.repeatMoveRate(sec: sec, span: span, family: .sine, mode: .inOut)
            return applyingFinalProcessing(to: from + (to - from) * repeatRate)

        default:
            if animationType.isKeyFrameSupported && animationType.isInterpolation {
                return splineInterpolatedValue(atFrame: frame, length: totalFrame, fps: fps)
            }
            if animationType.isKeyFrameSupported
                && (animationType.isInterpolationEasing || animationType == .interpolationBezier)
            {
                return wholeRateSplineValue(atFrame: frame, length: totalFrame, fps: fps)
            }
            if animationType == .linearBezier {
                return linearBezierValue(atFrame: frame, length: totalFrame, fps: fps)
            }
            if animationType.isKeyFrameSupported {
                return segmentEasedValue(atFrame: frame, length: totalFrame, fps: fps)
            }
            // キーフレーム非対応の残余経路: 全体率にイージングを適用し、
            // 有効な値の先頭と末尾を線形補間する
            let active = resolvedActiveValues
            let from = active.first ?? defaultValue
            let to = active.last ?? defaultValue
            return applyingFinalProcessing(to: from + (to - from) * easingRate(rate))
        }
    }

    /// 最終処理: Loop が有効なら剰余を取り、[minValue, maxValue] へクランプする。
    private func applyingFinalProcessing(to value: Double) -> Double {
        var value = value
        if loop != 0 {
            value = value.truncatingRemainder(dividingBy: loop)
        }
        return min(max(value, minValue), maxValue)
    }

    // MARK: - キーフレーム区間と値の取得（本家 GetKeyFrame / GetKeyFrameValue）

    /// frame を含むキーフレーム区間のインデックスと区間内率。
    ///
    /// キーフレーム位置は `位置 * fps / videoFPS` の整数演算で評価 FPS の
    /// 尺度へ換算する。キーフレームが無い、または基準 FPS が 0 の場合は
    /// 全体率をそのまま返す。
    private func keyFrameSegment(
        atFrame frame: Int, totalFrame: Int, fps: Int
    ) -> (index: Int, rate: Double) {
        let frames = keyFrames.frames
        if frames.isEmpty || videoFPS == 0 {
            return (0, Double(frame) / Double(totalFrame))
        }
        var index = 0
        var previous = 0
        for keyFrame in frames {
            let converted = keyFrame * fps / videoFPS
            if frame < converted {
                return (index, Double(frame - previous) / Double(converted - previous))
            }
            previous = converted
            index += 1
        }
        return (index, Double(frame - previous) / Double(totalFrame - previous))
    }

    /// インデックスに対応する値。範囲外なら最後の値、それも無ければ既定値。
    private func keyFrameValue(_ index: Int) -> Double {
        if values.indices.contains(index) {
            return values[index].value
        }
        return values.last?.value ?? defaultValue
    }

    // MARK: - 率のイージング（本家 GetEasingRate）

    /// 率に対するイージング適用。本家 `GetEasingRate(rate)`。
    ///
    /// _Int 版と非 _Int 版は同一の関数を返す。両者の違いは、どの率
    /// （全体率か区間内率か）とどの補間（スプラインか線形か）に使うか
    /// という評価経路だけにある。
    private func easingRate(_ rate: Double) -> Double {
        switch animationType {
        case .interpolation, .linear:
            return rate
        case .instant:
            return 0
        case .accelerationDeceleration:
            return (cos(rate * .pi + .pi) + 1) / 2
        case .linearBezier, .interpolationBezier:
            return bezier.value(atRate: rate)
        default:
            if let easing = animationType.easingFamilyAndMode {
                return easing.family.value(mode: easing.mode, rate: rate)
            }
            // 本家では NotImplementedException になる。定義済みの全ての型は
            // 上のいずれかで処理されるため、ここには到達しない。
            return rate
        }
    }

    // MARK: - 評価経路（キーフレーム系）

    /// 経路1: 補間移動・加減速移動。
    ///
    /// 区間内率を「連続座標」へ変換してから、区間の前後±2点の値を Cubic
    /// スプラインの重みで加重平均する。最初の区間は率を半分にして
    /// イージングし2倍、最後の区間は率を後半へ寄せてイージングし引き戻す
    /// ことで、座標を区間の外側まで連続させる。中間区間は変換しない。
    private func splineInterpolatedValue(atFrame frame: Int, length totalFrame: Int, fps: Int) -> Double {
        let (index, segmentRate) = keyFrameSegment(atFrame: frame, totalFrame: totalFrame, fps: fps)
        let keyFrameCount = keyFrames.frames.count
        let coordinate: Double
        if index == 0 && keyFrameCount == 0 {
            coordinate = easingRate(segmentRate)
        } else if index != 0 {
            coordinate = index == keyFrameCount
                ? easingRate((1 + segmentRate) / 2) * 2 - 1
                : segmentRate
        } else {
            coordinate = easingRate(segmentRate / 2) * 2
        }

        let segments = keyFrameCount + 1
        let cubic = Cubic()
        var weightedSum = 0.0
        var weightSum = 0.0
        for i in -2...2 {
            let valueIndex = index + i
            // 本家 Animation.cs の条件は (区間数 + 1) >= valueIndex であり、
            // 値の範囲を1つ超えた位置も含まれる。その位置の値は
            // keyFrameValue の末尾フォールバックにより最後の値になる。
            guard valueIndex >= 0, valueIndex <= segments + 1 else { continue }
            // 距離は符号付きで渡される（この経路では絶対値化しない）
            let distance = i <= 0 ? coordinate - Double(i) : Double(i) - coordinate
            let weight = cubic.weight(distance: distance)
            weightedSum += keyFrameValue(valueIndex) * weight
            weightSum += weight
        }
        return weightedSum / weightSum
    }

    /// 経路2: _Int イージング系と Interpolation_Bezier。
    ///
    /// 全体率にイージングを適用してから、全区間を対象に Cubic スプライン
    /// の重みで加重平均する。距離は絶対値化してから重みへ渡す。
    private func wholeRateSplineValue(atFrame frame: Int, length totalFrame: Int, fps: Int) -> Double {
        let easedRate = easingRate(Double(frame) / Double(totalFrame))
        let segments = keyFrames.frames.count + 1
        let position = easedRate * Double(segments)
        let base = Int(floor(position))
        let cubic = Cubic()
        var weightedSum = 0.0
        var weightSum = 0.0
        for j in -2...2 {
            let unclamped = base + j
            let valueIndex = min(max(unclamped, 0), segments)
            // インデックスはクランプするが、距離計算にはクランプ前の位置を使う
            let weight = cubic.weight(distance: abs(position - Double(unclamped)))
            weightedSum += keyFrameValue(valueIndex) * weight
            weightSum += weight
        }
        if weightSum == 0 {
            return keyFrameValue(min(max(base, 0), segments))
        }
        return weightedSum / weightSum
    }

    /// 経路3: Linear_Bezier。全体率にベジェを適用し、隣接2値を線形補間する。
    private func linearBezierValue(atFrame frame: Int, length totalFrame: Int, fps: Int) -> Double {
        let easedRate = easingRate(Double(frame) / Double(totalFrame))
        let segments = keyFrames.frames.count + 1
        let position = easedRate * Double(segments)
        let index = min(max(Int(floor(position)), 0), segments - 1)
        let fraction = position - Double(index)
        let start = keyFrameValue(index)
        let end = keyFrameValue(index + 1)
        return start + (end - start) * fraction
    }

    /// 経路4: その他のキーフレーム対応型（直線移動・瞬間移動・非 _Int
    /// イージング系）。区間内率にイージングを適用し、隣接2値を線形補間する。
    private func segmentEasedValue(atFrame frame: Int, length totalFrame: Int, fps: Int) -> Double {
        let (index, segmentRate) = keyFrameSegment(atFrame: frame, totalFrame: totalFrame, fps: fps)
        let easedRate = easingRate(segmentRate)
        let start = keyFrameValue(index)
        let end = keyFrameValue(index + 1)
        return start + (end - start) * easedRate
    }

    // MARK: - ランダム移動・反復移動の率（本家 GetRandomMoveRate / GetRepeatMoveRate）

    /// ランダム移動（Span > 0）の率。本家 `GetRandomMoveRate`。
    ///
    /// Span を1周期とする無次元位置の前後±2周期の乱数を Cubic スプライン
    /// の重みで加重する。補間移動の経路と違い、重み和での正規化はしない
    /// （カーネルの重み和が概ね1であることに依存する）。
    public static func randomMoveRate(
        seed: Int64, id: Int64, frame: Int, fps: Int, span: Double, seedOffset: Int64 = 0
    ) -> Double {
        let cubic = Cubic()
        let t = (fps == 0 || span == 0) ? 0.0 : Double(frame) / Double(fps) / span
        let base = Int(t) // C# のキャストと同じ0方向への切り捨て
        var sum = 0.0
        for i in -cubic.taps...cubic.taps {
            let random = StatelessRandom.getDouble(keys: [seed, id, Int64(base + i), seedOffset])
            sum += random * cubic.weight(distance: abs(Double(base + i) - t))
        }
        return sum
    }

    /// 反復移動（Span > 0）の率。本家 `GetRepeatMoveRate`。
    ///
    /// Span/2 を半周期とする三角波（0→1→0）を作り、その率にイージングを
    /// 適用する。Animation からの呼び出しは Sine / InOut 固定。
    public static func repeatMoveRate(
        sec: Double, span: Double, family: EasingFamily, mode: EasingMode
    ) -> Double {
        let half = span / 2
        let phase = sec.truncatingRemainder(dividingBy: span)
        let rate: Double
        if half == 0 {
            rate = 0
        } else if phase < half {
            rate = phase / half
        } else {
            rate = 1 - phase.truncatingRemainder(dividingBy: half) / half
        }
        return EasingFamily.getValue(family: family, mode: mode, rate: rate)
    }

    // MARK: - キーフレーム連動（本家 KeyFrames 変更イベントへの反応）

    /// キーフレーム追加への連動。
    ///
    /// 挿入する値は「その位置での現在値」であり、追加によって曲線は変わらない。
    /// 評価はキーフレームを追加する前の状態で行う。`values` へ値を挿入するのは
    /// キーフレーム対応の型だけであり、非対応の型はキーフレーム位置だけが増える。
    ///
    /// - Returns: 追加したら true。既に同じ位置がある場合は false。
    @discardableResult
    public mutating func insertKeyFrame(at frame: Int) -> Bool {
        guard !keyFrames.contains(frame) else { return false }
        let insertedValue = value(atFrame: frame, length: length, fps: videoFPS)
        guard let index = keyFrames.insert(frame) else { return false }
        if animationType.isKeyFrameSupported {
            values.insert(AnimationValue(insertedValue), at: min(index + 1, values.count))
        }
        return true
    }

    /// キーフレーム削除への連動。対応する `values` の要素も取り除く
    /// （キーフレーム対応の型のみ）。
    ///
    /// - Returns: 削除したら true。無い位置の場合は false。
    @discardableResult
    public mutating func removeKeyFrame(at frame: Int) -> Bool {
        guard let index = keyFrames.remove(frame) else { return false }
        if animationType.isKeyFrameSupported {
            let valueIndex = index + 1
            if values.indices.contains(valueIndex) {
                values.remove(at: valueIndex)
            }
        }
        return true
    }

    /// 全キーフレーム削除への連動。キーフレーム対応の型では値を
    /// 先頭（開始値）と末尾（終了値）だけに畳む（有効な値の数が
    /// キーフレーム数 + 2 から 2 へ戻るため）。
    ///
    /// - Returns: キーフレームの削除か値列の畳み込みが実際に
    ///   起きたら true（FE-R33-131-02 の無変更判定用）。
    @discardableResult
    public mutating func removeAllKeyFrames() -> Bool {
        let changed = !keyFrames.frames.isEmpty
            || (animationType.isKeyFrameSupported && values.count > 2)
        if animationType.isKeyFrameSupported, values.count > 2 {
            values = [values[0], values[values.count - 1]]
        }
        keyFrames = KeyFrames()
        return changed
    }

    /// キーフレームの位置だけを動かす。値はインデックスで対応する
    /// ため動かさない。隣のキーフレームを越えない範囲へ丸める
    /// （本家のタイムライン上のドラッグと同じ制約）。
    ///
    /// - Returns: 実際に動いたら true。
    @discardableResult
    public mutating func moveKeyFrame(from source: Int, to target: Int) -> Bool {
        guard let index = keyFrames.index(of: source) else { return false }
        let lower = index > 0 ? keyFrames.frames[index - 1] + 1 : 0
        let upper = index + 1 < keyFrames.frames.count
            ? keyFrames.frames[index + 1] - 1 : Int.max
        // 不整合な保存データ（重複・逆転した位置）では下限が上限を
        // 超え得る。その場合は動かさない（K19 レビュー (b) の境界）。
        guard lower <= upper else { return false }
        let clamped = min(max(target, lower), upper)
        guard clamped != source else { return false }
        var frames = keyFrames.frames
        frames[index] = clamped
        keyFrames = KeyFrames(frames: frames)
        return true
    }

    // MARK: - 種別変更と値列の正規化（本家 EndEditAsync の種別変更分岐）

    /// アニメーション種別を変更し、値列を新しい種別の有効な値の数・
    /// 意味へ組み替える単一操作（FE-R14-001）。
    ///
    /// 本家では編集開始時に `BeginEdit` が旧種別を記録し（Animation.cs:600）、
    /// 編集終了時の `EndEditAsync`（同 605–686）が旧種別→新種別の組合せで
    /// 値列を正規化する。Mac の記述子書き込みには編集セッション境界が
    /// 無いため、監査 Round 14 の指定により「種別変更＋値列正規化」を
    /// この1操作にまとめ、記述子の種別セッターは必ずここを通る。
    /// 変換に使う長さは注入済みの `length`（本家 `Length`、
    /// SetAnimationParameters 由来）である。
    ///
    /// 分岐は本家 EndEditAsync の種別変更側そのまま:
    /// - 新種別が「なし」: 先頭の値だけ残す。
    /// - 旧種別が「なし」: 先頭だけ残し、移動量指定なら移動量 0 を、
    ///   それ以外は先頭の値の複製を有効な値の数まで補う（定数 50 から
    ///   ランダム移動へ切り替えると終端値も 50 になるのはこの規則）。
    /// - 旧種別が「移動量指定」: 終端値 = 開始値 + 移動量 × 長さ。
    ///   新種別がキーフレーム対応なら、その区間を等分した位置の値を
    ///   線形に割り付ける。
    /// - 旧種別がキーフレーム非対応（ランダム移動・反復移動）:
    ///   移動量指定なら移動量 =（終了値 − 開始値）/ 長さ。
    ///   キーフレーム対応なら開始値→終了値を等分位置へ線形に割り付ける。
    ///   非対応同士（ランダム ⇔ 反復）は値列を変えない。
    /// - 旧種別がキーフレーム対応: 移動量指定なら
    ///   移動量 =（末尾の値 − 先頭の値）/ 長さ。非対応の新種別なら
    ///   終端値 = 末尾の値。対応同士は値列を変えない。
    ///
    /// 本家 EndEditAsync の「種別不変」側分岐（有効な値の数への
    /// 切り詰め・末尾値での補充）は対象外。Mac では値列の個数は
    /// キーフレーム追加・削除の連動と値書き込み側で維持されており、
    /// 読み込みデータの超過分は評価側が先頭 `activeValueCount` 個だけを
    /// 使うことで吸収する（保存時の往復保全を優先する判断）。
    /// 値列が空の異常データでは本家は例外になるが、ここでは入口で
    /// 既定値を種として実体化し、全分岐で結果の値列が空にならない
    /// ことを保証する（FE-R23-127-02。防御的な相違）。
    public mutating func changeAnimationType(to newType: AnimationType) {
        let oldType = animationType
        guard newType != oldType else { return }
        animationType = newType

        // 値列が空の異常データでは、既定値を種として実体化してから
        // 組み替える（FE-R23-127-02）。これにより、値列を変えない
        // 分岐（ランダム ⇔ 反復）や先頭だけ残す分岐（「なし」への
        // 遷移）でも結果が空にならない。
        if values.isEmpty {
            values = [AnimationValue(defaultValue)]
        }

        if newType == .none {
            values = Array(values.prefix(1))
            return
        }
        // 以降の分岐では先頭の値が必ず要る。入口の種付けで空でない
        // ことが保証される（フォールバックは念のための防御）。
        let first = values.first ?? AnimationValue(defaultValue)
        if oldType == .none {
            if newType == .movementAmount {
                values = [first, AnimationValue(0)]
            } else {
                values = [first] + Array(
                    repeating: first, count: activeValueCount - 1
                )
            }
            return
        }
        if oldType == .movementAmount {
            let from = first.value
            let delta = values.dropFirst().first?.value ?? 0
            if !newType.isKeyFrameSupported {
                values = [first, AnimationValue(from + delta * Double(length))]
            } else {
                let count = activeValueCount - 1
                values = [first] + (1...count).map { x in
                    AnimationValue(
                        from + delta * Double(length) * Double(x) / Double(count)
                    )
                }
            }
            return
        }
        if !oldType.isKeyFrameSupported {
            let from = first.value
            let to = values.dropFirst().first?.value ?? from
            if newType == .movementAmount {
                values = [first, AnimationValue((to - from) / Double(length))]
            } else if newType.isKeyFrameSupported {
                let count = activeValueCount - 1
                values = [first] + (1...count).map { x in
                    AnimationValue(from + (to - from) * Double(x) / Double(count))
                }
            }
            return
        }
        if newType == .movementAmount {
            let last = values.dropFirst().last?.value ?? first.value
            values = [first, AnimationValue((last - first.value) / Double(length))]
        } else if !newType.isKeyFrameSupported {
            let end = values.dropFirst().last?.value ?? first.value
            values = [first, AnimationValue(end)]
        }
    }

    // MARK: - Undo 記録用の状態写し

    /// 編集の前後状態の写し（種別と値列のみ）。
    ///
    /// 種別変更（`changeAnimationType`）は値列を組み替える不可逆な
    /// 操作であるため、Undo で種別だけを戻しても変更前の値列は
    /// 復元できない。記録側はこの写しを変更前後の組として保持し、
    /// Undo/Redo では `restoreRecordedState` でそのまま書き戻す
    /// （FE-R23-127-01）。値列全体を一体で記録する編集（移動量指定
    /// の第2値。実体化による値列の個数の変化まで復元するため、
    /// FE-R25-128-01）でも同じ写しを使う。キーフレーム列・長さ等の
    /// 評価文脈は所有アイテムから注入されるもので、これらの編集
    /// では変わらないため、写しには含めない。
    public struct RecordedState: Equatable, Sendable {
        public var animationType: AnimationType
        public var values: [AnimationValue]

        public init(animationType: AnimationType, values: [AnimationValue]) {
            self.animationType = animationType
            self.values = values
        }
    }

    /// 現在の種別と値列の写し（Undo 記録用）。
    public var recordedState: RecordedState {
        RecordedState(animationType: animationType, values: values)
    }

    /// 記録済みの状態をそのまま書き戻す。種別変更と、値列全体を
    /// 一体で記録する編集（移動量指定の第2値）の Undo/Redo で使う
    /// 復元経路であり、正規化（`changeAnimationType`）は再実行
    /// しない。通常の編集経路では使わない（種別変更は
    /// `changeAnimationType`、値の書き込みは `setValue` 等を通す）。
    public mutating func restoreRecordedState(_ state: RecordedState) {
        animationType = state.animationType
        values = state.values
    }

    /// 再生ヘッド位置が属する区間のインデックス。区間は
    /// [0, キーフレーム..., 長さ] の境界で区切られ、`values` の
    /// インデックスと一致する（区間 i の開始値が values[i]）。
    public func segmentIndex(atFrame frame: Int) -> Int {
        keyFrames.frames.count { $0 <= frame }
    }

    /// 区間の開始値を書き換える（定義範囲へクランプ）。値列が短い
    /// 不完全なデータでは、まず評価上の有効値列へ展開してから対象
    /// 位置だけを書き換える。有効な値の個数は本家の
    /// GetActiveValueCount と同じくキーフレーム数 + 2（開始値、
    /// 各キーフレーム位置の値、最終端点の値）。展開せずに対象位置
    /// までだけ補うと、代用規則（末尾の値）で読まれていた対象外の
    /// 位置、特に最終端点まで新しい値に変わってしまう
    /// （K19-03／R20-114-02）。既に揃っている正常なデータは
    /// 展開しない。区間の範囲外のインデックスは受け付けない。
    public mutating func setValue(_ value: Double, atSegment index: Int) {
        guard index >= 0, index <= keyFrames.frames.count else { return }
        if animationType.isKeyFrameSupported {
            let activeCount = keyFrames.frames.count + 2
            while values.count < activeCount {
                values.append(AnimationValue(keyFrameValue(values.count)))
            }
        }
        while values.count <= index {
            values.append(AnimationValue(keyFrameValue(values.count)))
        }
        values[index] = AnimationValue(clamped(value))
    }

    /// 値列のインデックス指定の書き換え（キーフレーム区間ではない
    /// 値の編集用。移動量指定の第2値など、FE-R13-003）。
    ///
    /// 値列が対象位置まで実体化していない場合は、読み取り側の代用
    /// 規則（範囲外は末尾の値、無ければ既定値）と同じ値で対象位置
    /// まで実体化してから書き換える（区間版 `setValue(_:atSegment:)`
    /// の実体化と同じ規則）。クランプ範囲は呼び出し側が渡す: 移動量
    /// 指定の第2値では本家がその値のスライダの Min/Max を絶対制限の
    /// 対称範囲（±最大絶対値）へ置き換えるため、定義範囲
    /// [minValue, maxValue] へは固定しない。
    public mutating func setValue(
        _ value: Double, atValueIndex index: Int, clampRange: ClosedRange<Double>
    ) {
        guard index >= 0 else { return }
        while values.count <= index {
            values.append(AnimationValue(keyFrameValue(values.count)))
        }
        values[index] = AnimationValue(
            min(max(value, clampRange.lowerBound), clampRange.upperBound))
    }

    /// 先頭の値を書き換える。本家 `SetFirstValue`。
    /// 値が無い場合は1つ追加する。
    public mutating func setFirstValue(_ value: Double) {
        if values.isEmpty {
            values = [AnimationValue(value)]
        } else {
            values[0] = AnimationValue(value)
        }
    }

    /// 分割（左側を取り除く）への連動。本家 `KeyFrames.RemovesLeft` の
    /// 変更イベントに対する `Animation` 側の反応。
    ///
    /// 切断位置での現在値を新しい開始値とし、取り除かれるキーフレームの
    /// 値を落とす。評価はキーフレームが変わる前の状態（この `Animation`
    /// が保持する写し）で行うため、所有アイテムはキーフレーム集合を
    /// 更新する前にこのメソッドを呼ぶこと。キーフレーム非対応の型では
    /// 値は変わらない。
    ///
    /// - Parameters:
    ///   - cutFrame: 切断位置（アイテム内相対フレーム、切断前の座標）。
    ///   - removedCount: 取り除かれるキーフレームの個数。
    public mutating func applyKeyFramesRemovesLeft(cutFrame: Int, removedCount: Int) {
        guard animationType.isKeyFrameSupported else { return }
        let cutValue = value(atFrame: cutFrame, length: length, fps: videoFPS)
        values = [AnimationValue(cutValue)] + Array(values.dropFirst(removedCount + 1))
    }

    /// 分割（右側を取り除く）への連動。本家 `KeyFrames.RemovesRight` の
    /// 変更イベントに対する `Animation` 側の反応。
    ///
    /// 切断位置での現在値を新しい終了値とし、取り除かれるキーフレームの
    /// 値と元の終了値を落とす。評価と呼び出し順の注意は
    /// `applyKeyFramesRemovesLeft` と同じ。
    public mutating func applyKeyFramesRemovesRight(cutFrame: Int, removedCount: Int) {
        guard animationType.isKeyFrameSupported else { return }
        let cutValue = value(atFrame: cutFrame, length: length, fps: videoFPS)
        let keepCount = max(0, values.count - (removedCount + 1))
        values = Array(values.prefix(keepCount)) + [AnimationValue(cutValue)]
    }
}
