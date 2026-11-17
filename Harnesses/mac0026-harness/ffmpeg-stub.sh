#!/bin/sh
# MAC-0026 検証用スタブ ffmpeg。
# 引数をログへ記録し、エンコード起動では stdin を捕捉して
# 出力先へダミーを書く。mux 起動（-c copy）では第2入力を出力へ写す。
# 作業ディレクトリは「最後の引数（出力パス）のディレクトリ」で決める。

last=""
for a in "$@"; do last="$a"; done
workdir=$(dirname "$last")
capture="$workdir/capture"
mkdir -p "$capture"
echo "CALL: $*" >> "$workdir/stub.log"

is_mux=0
prev=""
in1=""
in2=""
for a in "$@"; do
  if [ "$prev" = "-i" ]; then
    if [ -z "$in1" ]; then in1="$a"; else in2="$a"; fi
  fi
  if [ "$a" = "copy" ]; then is_mux=1; fi
  prev="$a"
done

if [ "$is_mux" = "1" ]; then
  cp "$in2" "$last"
  exit 0
fi

cat > "$capture/$(basename "$last").stdin"
printf 'stub-output' > "$last"
exit 0
