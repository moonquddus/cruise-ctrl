import sys
import unittest
from pathlib import Path

root = Path(__file__).parent
sys.path.insert(0, str(root.parent / "plugin"))
from approve import dialog


def screen(name):
    return (root / "screens" / name).read_text()


class Dialog(unittest.TestCase):
    def test_approves_a_bash_prompt(self):
        self.assertEqual(dialog(screen("proceed.txt")), "Do you want to proceed?")

    def test_approves_a_wrapped_sandbox_prompt(self):
        self.assertEqual(dialog(screen("sandbox-wrapped.txt")), "Network request outside of sandbox")

    def test_ignores_a_question_from_claude(self):
        self.assertIsNone(dialog(screen("ask.txt")))

    def test_ignores_a_dynamic_workflow(self):
        self.assertIsNone(dialog(screen("workflow.txt")))

    def test_ignores_the_input_box(self):
        self.assertIsNone(dialog(screen("input-box.txt")))

    def test_ignores_a_prompt_in_prose(self):
        self.assertIsNone(dialog(screen("prose.txt")))

    def test_ignores_a_prompt_with_another_option_selected(self):
        self.assertIsNone(dialog(screen("moved.txt")))


if __name__ == "__main__":
    unittest.main()
