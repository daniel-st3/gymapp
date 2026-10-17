import unittest
from prepare_review_shortcut import workflow

class ReviewShortcutContractTests(unittest.TestCase):
    def test_model_output_and_receipt_chain_remain_connected(self):
        actions = workflow('com.example.generic', 'TESTTEAM')['WFWorkflowActions']
        prepare, model, save = [a['WFWorkflowActionParameters'] for a in actions]
        self.assertEqual(model['WFLLMModel'], 'ChatGPT')
        self.assertEqual(model['WFGenerativeResultType'], 'Text')
        self.assertEqual(model['WFLLMPrompt']['Value']['attachmentsByRange']['{0, 1}']['OutputUUID'], prepare['UUID'])
        self.assertEqual(save['reviewJSON']['Value']['attachmentsByRange']['{0, 1}']['OutputUUID'], model['UUID'])
        self.assertEqual(save['AppIntentDescriptor']['BundleIdentifier'], 'com.example.generic')
        self.assertEqual(save['AppIntentDescriptor']['AppIntentIdentifier'], 'SaveWorkoutReviewIntent')
        self.assertEqual(len({x['UUID'] for x in [prepare,model,save]}), 3)
    def test_unsupported_provider_never_falls_back(self):
        with self.assertRaises(ValueError): workflow('com.example.generic','TESTTEAM','paid-fallback')
        self.assertEqual(workflow('com.example.generic','TESTTEAM','ask')['WFWorkflowActions'][1]['WFWorkflowActionParameters']['WFLLMModel']['Value']['Type'],'Ask')

    def test_generic_check_never_uses_history_preparation(self):
        result = workflow('com.example.generic', 'TESTTEAM', connection_check=True)
        self.assertEqual(result['WFWorkflowName'], 'Little Lift Connection Check')
        prepare = result['WFWorkflowActions'][0]['WFWorkflowActionParameters']
        self.assertEqual(prepare['AppIntentDescriptor']['AppIntentIdentifier'], 'PrepareCoachConnectionCheckIntent')
        self.assertNotIn('PrepareWorkoutReviewIntent', str(result))
