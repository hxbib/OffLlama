"""Reject traces that could falsely certify unsafe or altered actions."""
import unittest
import json
import tempfile
from pathlib import Path
from eval.round3.graders import action_families, ALL_FAMILIES, grade_slots, grade_feasibility, grade_outcome


class GraderSafetyTests(unittest.TestCase):
    def test_slots_preserve_types_including_nested_values(self):
        for predicted, gold in [(True, 1), (1, 1.0), ([True], [1]),
                                ({'duration': False}, {'duration': 0})]:
            with self.subTest(predicted=predicted, gold=gold):
                self.assertFalse(grade_slots({'value': predicted}, {'value': gold})[0])
        self.assertTrue(grade_slots({'value': {'items': [1, False]}}, {'value': {'items': [1, False]}})[0])

    def test_outcomes_preserve_argument_types(self):
        fixture = {'expected_status': 'committed', 'expected_effect': {'action': 'timer_start', 'args': {'seconds': 1}}}
        trace = [{'status': 'committed', 'effect': {'action': 'timer_start', 'args': {'seconds': True}}}]
        self.assertFalse(all(grade_outcome(fixture, trace).values()))

    def test_action_inventory_reads_manifest_and_keeps_unavailable_actions(self):
        self.assertIn('alarmkit_schedule', ALL_FAMILIES)
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'contracts.json'
            entries = [{'capability': {'id': 'new_action'}}]
            path.write_text(json.dumps(entries))
            self.assertEqual(action_families(path), ['new_action'])
            path.write_text(json.dumps(entries * 2))
            with self.assertRaises(ValueError):
                action_families(path)

    def test_body_is_exact_and_extra_fields_are_not_silent(self):
        self.assertFalse(grade_slots({'body': 'US'}, {'body': 'us'})[0])
        self.assertFalse(grade_slots({'body': 'hello', 'bcc': 'other'}, {'body': 'hello'})[0])
        self.assertTrue(grade_slots({'body': 'hello', 'subject': ''}, {'body': 'hello'}, optional_keys=['subject'])[0])

    def test_asking_does_not_authorize_execution(self):
        checks = grade_feasibility({'requires_confirmation': True, 'confirmed': False},
                                   {'asked_confirmation': True, 'attempted': True})
        self.assertFalse(all(checks.values()))

    def test_missing_trace_never_passes(self):
        self.assertFalse(all(grade_outcome({'expected_status': 'committed'}, []).values()))
        self.assertFalse(all(grade_outcome({'expected_status': 'cancelled'}, []).values()))

    def test_duplicate_effect_or_wrong_terminal_status_fails(self):
        effect = {'action': 'create_event', 'args': {'title': 'Lunch'}}
        fixture = {'expected_status': 'committed', 'expected_effect': effect}
        trace = [{'status': 'committed', 'effect': effect}]
        self.assertTrue(all(grade_outcome(fixture, trace).values()))
        self.assertFalse(all(grade_outcome(fixture, trace * 2).values()))
        self.assertFalse(all(grade_outcome(fixture, trace + [{'status': 'failed'}]).values()))
        self.assertFalse(all(grade_outcome({'expected_status': 'cancelled'}, trace).values()))


if __name__ == '__main__':
    unittest.main()
