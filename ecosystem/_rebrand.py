import os
import sys

ECO = r"E:\Projects\AXIOM\ecosystem"

REPLACEMENTS = [
    ("module axiom.", "module xiom."),
    ("package axiom_ecosystem", "package xiom_ecosystem"),
    ("use axiom.", "use xiom."),
    ("axiom-", "xiom-"),
    ("axiomc", "xiomc"),
    ("AXIOM", "XIOM"),
    (".ax\"", ".xi\""),
    ("axiom", "xiom"),
]

def process_file(ax_path):
    with open(ax_path, "r", encoding="utf-8") as f:
        content = f.read()

    new_content = content
    for old, new in REPLACEMENTS:
        new_content = new_content.replace(old, new)

    xi_path = ax_path[:-3] + ".xi"
    with open(xi_path, "w", encoding="utf-8") as f:
        f.write(new_content)
    return xi_path

def main():
    count = 0
    for root, dirs, files in os.walk(ECO):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fname in files:
            if fname.endswith(".ax") and fname != "_rebrand.py":
                ax_path = os.path.join(root, fname)
                xi_path = process_file(ax_path)
                count += 1
                print(f"  {ax_path}  ->  {xi_path}")
    print(f"\nProcessed {count} files.")
    return count

if __name__ == "__main__":
    sys.exit(main())
