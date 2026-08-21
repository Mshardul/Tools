import unittest

from case_transform import transform_case


class CaseTransformTests(unittest.TestCase):
    def test_to_snake(self):
        self.assertEqual(transform_case("HelloWorld", "snake"), "hello_world")

    def test_to_camel(self):
        self.assertEqual(transform_case("hello_world", "camel"), "helloWorld")

    def test_to_pascal(self):
        self.assertEqual(transform_case("hello-world", "pascal"), "HelloWorld")

    def test_to_kebab(self):
        self.assertEqual(transform_case("HelloWorld", "kebab"), "hello-world")

    def test_unknown_target(self):
        with self.assertRaises(ValueError):
            transform_case("x", "nope")


if __name__ == "__main__":
    unittest.main()
