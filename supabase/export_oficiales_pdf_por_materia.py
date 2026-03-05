#!/usr/bin/env python3
import csv
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from pypdf import PdfReader


BULLET = "\u00bb"


def clean_text(value: str) -> str:
    return " ".join(value.replace("\r", " ").split())


def normalize_ascii(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value)
    return "".join(ch for ch in decomposed if not unicodedata.combining(ch))


def norm_upper(value: str) -> str:
    return normalize_ascii(value).upper()


Q_ONLY_RE = re.compile(r"^(\d{1,4})\.$")
Q_END_RE = re.compile(r"(\d{1,4})\.$")
DIGITS_RE = re.compile(r"^\d{3,}$")


HEADER_PREFIXES = (
    "BANCO DE PREGUNTAS PARA EL PROCESO DE ASCENSO POR CONCURSO DE OFICIALES PNP DEL ANO",
    "GENERADO POR SISTEMA DE EVALUACION DE CONOCIMIENTO POLICIAL",
)
HEADER_EXACT = {
    "2025 - PROMOCION 2026",
    "(POLICIA)",
    "MATERIAS COMUNES",
    "MATERIAS DE ESPECIALIDAD",
}
HEADER_PAGE_RE = re.compile(r"^PAGINA:\s*\d+$")


HEADING_PREFIXES = (
    "CONSTITUCION POLITICA DEL PERU",
    "DECLARACION UNIVERSAL",
    "LEY ",
    "DECRETO LEGISLATIVO",
    "D.LEG",
    "DECRETO SUPREMO",
    "MANUAL DEL",
    "CODIGO ",
)


TITLE_OVERRIDES = {
    1: "CONSTITUCION POLITICA DEL PERU",
    201: "DECLARACION UNIVERSAL DE LOS DERECHOS HUMANOS",
    231: "DECRETO LEGISLATIVO 1267 - LEY DE LA PNP",
    411: "DECRETO LEGISLATIVO 1149 - LEY DE CARRERA Y SITUACION DEL PERSONAL PNP",
    631: "DECRETO LEGISLATIVO 1291 - LUCHA CONTRA LA CORRUPCION EN EL SECTOR INTERIOR",
    731: "LEY 30714 - REGIMEN DISCIPLINARIO DE LA PNP",
    981: "DECRETO LEGISLATIVO 1318 - FORMACION PROFESIONAL DE LA PNP",
    1061: "DECRETO SUPREMO 021-2019-JUS - TUO LEY 27806 TRANSPARENCIA Y ACCESO A INFORMACION",
    1181: "LEY 31873 - PROCESOS DE ASCENSOS DEL PERSONAL PNP",
    1261: "LEY 27444 - LEY DEL PROCEDIMIENTO ADMINISTRATIVO GENERAL",
    1501: "DECRETO LEGISLATIVO 957 - CODIGO PROCESAL PENAL",
    1841: "DECRETO LEGISLATIVO 635 - CODIGO PENAL",
    2281: "DECRETO LEGISLATIVO 1186 - USO DE LA FUERZA POR PARTE DE LA PNP",
    2371: "DECRETO LEGISLATIVO 1241 - LUCHA CONTRA EL TRAFICO ILICITO DE DROGAS",
    2461: "DECRETO LEGISLATIVO 1106 - LUCHA CONTRA EL LAVADO DE ACTIVOS",
    2561: "LEY 30364 - VIOLENCIA CONTRA LAS MUJERES E INTEGRANTES DEL GRUPO FAMILIAR",
    2661: "MANUAL DEL OFICIAL DE ESTADO MAYOR (RD 245-DIRGEN/EMG)",
    2761: "LEY 30077 - CONTRA EL CRIMEN ORGANIZADO",
    2861: "LEY 32130 - MODIFICA EL CODIGO PROCESAL PENAL",
    2951: "DECRETO LEGISLATIVO 1611 - PREVENCION E INVESTIGACION DEL DELITO DE EXTORSION",
}


@dataclass
class Question:
    numero: int
    pagina_inicio: int
    enunciado: str
    alternativas: List[str]
    respuesta_texto: str
    respuesta_ref: str
    ubicacion: str
    codigo_fuente: str
    materia_inicio: int = 0
    materia_nombre: str = ""


def detect_qstart(line: str) -> Optional[Tuple[int, str]]:
    m = Q_ONLY_RE.match(line)
    if m:
        n = int(m.group(1))
        if 1 <= n <= 3000:
            return n, ""

    m2 = Q_END_RE.search(line)
    if m2:
        n = int(m2.group(1))
        if 1 <= n <= 3000:
            return n, line[: m2.start()].strip()
    return None


def parse_questions(pdf_path: Path) -> List[Question]:
    reader = PdfReader(str(pdf_path))
    lines: List[Tuple[int, str, str]] = []

    for page_no, page in enumerate(reader.pages, start=1):
        for raw in (page.extract_text() or "").split("\n"):
            line = clean_text(raw)
            if not line:
                continue
            nline = norm_upper(line)
            if any(nline.startswith(prefix) for prefix in HEADER_PREFIXES):
                continue
            if nline in HEADER_EXACT:
                continue
            if HEADER_PAGE_RE.match(nline):
                continue
            lines.append((page_no, line, nline))

    questions: List[Question] = []
    state = "await_q"
    stem_lines: List[str] = []
    current = None
    opt_lines: List[str] = []
    ref_lines: List[str] = []
    expect_ubic = False

    def finalize_current() -> None:
        nonlocal current, opt_lines, ref_lines
        if current is None:
            return
        raw_opts = clean_text(" ".join(opt_lines))
        parts = [clean_text(x) for x in raw_opts.split(BULLET)]
        parts = [p for p in parts if p]
        if len(parts) >= 6:
            alternatives = parts[:5]
            answer_text = parts[5] if len(parts) == 6 else clean_text(" ".join(parts[5:]))
        else:
            alternatives = (parts + ["", "", "", "", ""])[:5]
            answer_text = ""

        question = Question(
            numero=current["numero"],
            pagina_inicio=current["pagina_inicio"],
            enunciado=clean_text(current["enunciado"]),
            alternativas=alternatives,
            respuesta_texto=clean_text(answer_text),
            respuesta_ref=clean_text(" ".join(ref_lines)),
            ubicacion=current["ubicacion"],
            codigo_fuente=current["codigo_fuente"],
        )
        questions.append(question)
        current = None
        opt_lines = []
        ref_lines = []

    for page_no, line, nline in lines:
        if state == "await_q":
            start = detect_qstart(line)
            if start:
                numero, prefix = start
                stem_parts = stem_lines.copy()
                if prefix:
                    stem_parts.append(prefix)
                current = {
                    "numero": numero,
                    "pagina_inicio": page_no,
                    "enunciado": clean_text(" ".join(stem_parts)),
                    "ubicacion": "",
                    "codigo_fuente": "",
                }
                stem_lines = []
                opt_lines = []
                ref_lines = []
                expect_ubic = False
                state = "options"
                continue

            stem_lines.append(line)
            if len(stem_lines) > 30:
                stem_lines = stem_lines[-30:]
            continue

        if state == "options":
            if "RESPUESTA:" in nline:
                split_parts = re.split(r"RESPUESTA\s*:", line, flags=re.IGNORECASE)
                before = split_parts[0].strip() if split_parts else ""
                after = split_parts[1].strip() if len(split_parts) > 1 else ""
                if before:
                    opt_lines.append(before)
                if after:
                    ref_lines.append(after)
                state = "meta"
            else:
                opt_lines.append(line)
            continue

        if state == "meta":
            start = detect_qstart(line)
            if start and "UBICACION" not in nline and "CODIGO" not in nline:
                finalize_current()
                numero, prefix = start
                current = {
                    "numero": numero,
                    "pagina_inicio": page_no,
                    "enunciado": clean_text(prefix),
                    "ubicacion": "",
                    "codigo_fuente": "",
                }
                stem_lines = []
                opt_lines = []
                ref_lines = []
                expect_ubic = False
                state = "options"
                continue

            if "UBICACION:" in nline:
                m = re.search(r"UBICACION\s*:\s*(\d+)", nline)
                if m:
                    current["ubicacion"] = m.group(1)
                    expect_ubic = False
                else:
                    expect_ubic = True
                continue

            if "CODIGO:" in nline or nline.strip() in {"CODIGO:", "CODIGO"}:
                m = re.search(r"CODIGO\s*:\s*(\S+)", nline)
                if m:
                    current["codigo_fuente"] = m.group(1)
                finalize_current()
                expect_ubic = False
                state = "await_q"
                continue

            if expect_ubic and DIGITS_RE.match(nline):
                current["ubicacion"] = nline
                expect_ubic = False
                continue

            ref_lines.append(line)
            continue

    if current is not None:
        finalize_current()

    return questions


def needs_continuation(title_n: str) -> bool:
    endings = (" DE", " DEL", " Y", " Y SU", " A LA", " AL", " D.L.", " D.L", " N", " N°")
    if any(title_n.endswith(e) for e in endings):
        return True
    return title_n.count("(") > title_n.count(")")


def detect_section_starts(pdf_path: Path) -> List[Tuple[int, str, str]]:
    reader = PdfReader(str(pdf_path))
    starts: List[Tuple[int, str, str]] = []
    seen = set()

    for page in reader.pages:
        raw_lines = [clean_text(x) for x in (page.extract_text() or "").split("\n") if clean_text(x)]
        nlines = [norm_upper(x) for x in raw_lines]

        first_q_idx = None
        first_q_num = None
        for idx, line in enumerate(raw_lines[:140]):
            start = detect_qstart(line)
            if start:
                first_q_num = start[0]
                first_q_idx = idx
                break
        if first_q_idx is None:
            continue

        pre = list(zip(raw_lines[:first_q_idx], nlines[:first_q_idx]))
        filtered = []
        for line, nline in pre:
            if any(nline.startswith(prefix) for prefix in HEADER_PREFIXES):
                continue
            if nline in HEADER_EXACT:
                continue
            if HEADER_PAGE_RE.match(nline):
                continue
            filtered.append((line, nline))
        if not filtered:
            continue

        all_n = " ".join(n for _, n in filtered)
        if "RESPUESTA:" in all_n or "UBICACION:" in all_n or "CODIGO:" in all_n:
            continue
        if any(BULLET in l for l, _ in filtered):
            continue

        candidate_idx = None
        for idx, (line, nline) in enumerate(filtered):
            if len(line) < 25:
                continue
            if "?" in line or "¿" in line:
                continue
            if detect_qstart(line):
                continue
            if any(nline.startswith(prefix) for prefix in HEADING_PREFIXES):
                candidate_idx = idx
                break
        if candidate_idx is None:
            continue

        title = filtered[candidate_idx][0]
        title_n = filtered[candidate_idx][1]
        if needs_continuation(title_n):
            if candidate_idx + 1 < len(filtered):
                nxt_line, nxt_n = filtered[candidate_idx + 1]
                if (
                    len(nxt_line) <= 100
                    and "?" not in nxt_line
                    and "¿" not in nxt_line
                    and BULLET not in nxt_line
                    and not detect_qstart(nxt_line)
                    and "RESPUESTA:" not in nxt_n
                    and "UBICACION:" not in nxt_n
                    and "CODIGO:" not in nxt_n
                ):
                    title = clean_text(f"{title} {nxt_line}")

        canonical_title = TITLE_OVERRIDES.get(first_q_num, title)
        if first_q_num not in seen:
            starts.append((first_q_num, title, canonical_title))
            seen.add(first_q_num)

    starts.sort(key=lambda x: x[0])
    return starts


def strip_title_prefix(question_text: str, title: str) -> str:
    q = clean_text(question_text)
    qn = norm_upper(q)
    tn = norm_upper(title)
    if qn.startswith(tn):
        q = q[len(title) :].lstrip(" .:-")
    return clean_text(q)


def normalize_compare(value: str) -> str:
    n = norm_upper(value)
    n = re.sub(r"[^A-Z0-9]+", " ", n)
    return " ".join(n.split())


def resolve_answer_letter(alternatives: List[str], answer_text: str) -> str:
    letters = ["A", "B", "C", "D", "E"]
    answer_n = normalize_compare(answer_text)
    for idx, alt in enumerate(alternatives):
        alt_n = normalize_compare(alt)
        if not answer_n or not alt_n:
            continue
        if answer_n == alt_n or answer_n in alt_n or alt_n in answer_n:
            return letters[idx]
    return ""


def slugify(value: str) -> str:
    ascii_value = normalize_ascii(value).lower()
    ascii_value = re.sub(r"[^a-z0-9]+", "_", ascii_value)
    ascii_value = re.sub(r"_+", "_", ascii_value).strip("_")
    return ascii_value or "materia"


def assign_materias(
    questions: List[Question], starts: List[Tuple[int, str, str]]
) -> List[Tuple[int, int, str, str]]:
    if not starts:
        return []

    max_num = max(q.numero for q in questions)
    ranges = []
    for idx, (start_num, raw_title, canonical_title) in enumerate(starts):
        end_num = starts[idx + 1][0] - 1 if idx + 1 < len(starts) else max_num
        ranges.append((start_num, end_num, raw_title, canonical_title))

    ranges.sort(key=lambda x: x[0])
    current_idx = 0
    for q in sorted(questions, key=lambda x: x.numero):
        while current_idx + 1 < len(ranges) and q.numero > ranges[current_idx][1]:
            current_idx += 1
        start_num, _, raw_title, canonical_title = ranges[current_idx]
        q.materia_inicio = start_num
        q.materia_nombre = canonical_title
        if q.numero == start_num:
            q.enunciado = strip_title_prefix(q.enunciado, raw_title)
    return ranges


def write_csvs(
    output_dir: Path, questions: List[Question], ranges: List[Tuple[int, int, str, str]]
) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)
    grouped = {}
    for start_num, end_num, _, canonical_title in ranges:
        grouped[start_num] = {
            "title": canonical_title,
            "end": end_num,
            "rows": [],
        }

    for q in sorted(questions, key=lambda x: x.numero):
        if q.materia_inicio not in grouped:
            continue
        grouped[q.materia_inicio]["rows"].append(q)

    headers = [
        "numero_oficial",
        "codigo_pregunta",
        "materia_inicio",
        "materia_nombre",
        "enunciado",
        "alternativa_a",
        "alternativa_b",
        "alternativa_c",
        "alternativa_d",
        "alternativa_e",
        "respuesta_texto",
        "respuesta_letra",
        "respuesta_ref",
        "ubicacion_fuente",
        "codigo_fuente",
        "pagina_pdf",
    ]

    summary_rows = []
    for start_num in sorted(grouped):
        info = grouped[start_num]
        end_num = info["end"]
        title = info["title"]
        rows: List[Question] = info["rows"]
        filename = f"{start_num:04d}-{end_num:04d}_{slugify(title)}.csv"
        out_path = output_dir / filename

        with out_path.open("w", newline="", encoding="utf-8-sig") as f:
            writer = csv.DictWriter(f, fieldnames=headers)
            writer.writeheader()
            for q in rows:
                alternatives = (q.alternativas + ["", "", "", "", ""])[:5]
                writer.writerow(
                    {
                        "numero_oficial": q.numero,
                        "codigo_pregunta": f"OFI-{q.numero:04d}",
                        "materia_inicio": q.materia_inicio,
                        "materia_nombre": q.materia_nombre,
                        "enunciado": q.enunciado,
                        "alternativa_a": alternatives[0],
                        "alternativa_b": alternatives[1],
                        "alternativa_c": alternatives[2],
                        "alternativa_d": alternatives[3],
                        "alternativa_e": alternatives[4],
                        "respuesta_texto": q.respuesta_texto,
                        "respuesta_letra": resolve_answer_letter(alternatives, q.respuesta_texto),
                        "respuesta_ref": q.respuesta_ref,
                        "ubicacion_fuente": q.ubicacion,
                        "codigo_fuente": q.codigo_fuente,
                        "pagina_pdf": q.pagina_inicio,
                    }
                )

        summary_rows.append(
            {
                "archivo_csv": filename,
                "materia_nombre": title,
                "inicio": start_num,
                "fin": end_num,
                "total_preguntas": len(rows),
            }
        )

    summary_path = output_dir / "00_resumen_materias.csv"
    with summary_path.open("w", newline="", encoding="utf-8-sig") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=["archivo_csv", "materia_nombre", "inicio", "fin", "total_preguntas"],
        )
        writer.writeheader()
        writer.writerows(summary_rows)


def main() -> None:
    base = Path(__file__).resolve().parent
    pdf_path = base / "Banco_OficialSuperio_Final_sin_marca.pdf"
    output_dir = base / "oficiales-banco-por-materia"

    if not pdf_path.exists():
        raise FileNotFoundError(f"No se encontro el PDF: {pdf_path}")

    questions = parse_questions(pdf_path)
    nums = [q.numero for q in questions]
    if len(questions) != 3000 or len(set(nums)) != 3000 or min(nums) != 1 or max(nums) != 3000:
        raise RuntimeError(
            f"Extraccion incompleta: total={len(questions)} unicos={len(set(nums))} min={min(nums)} max={max(nums)}"
        )

    starts = detect_section_starts(pdf_path)
    starts_by_num: Dict[int, Tuple[str, str]] = {n: (raw, canon) for n, raw, canon in starts}
    for n, t in TITLE_OVERRIDES.items():
        if n not in starts_by_num:
            starts.append((n, t, t))
    starts = sorted(starts, key=lambda x: x[0])

    ranges = assign_materias(questions, starts)
    write_csvs(output_dir, questions, ranges)

    print(f"Preguntas extraidas: {len(questions)}")
    print(f"Materias detectadas: {len(ranges)}")
    print(f"Salida: {output_dir}")


if __name__ == "__main__":
    main()
