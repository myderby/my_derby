-- User requested reducing the annual horse insurance rate from 4% to 2%.
INSERT INTO my_derby.economy_config(key,amount,policy_status,explanation)
VALUES('HORSE_INSURANCE_ANNUAL_BASIS_POINTS',200,'PROVISIONAL',
 'User-configured annual insurance premium: 2% of purchase amount, divided across four-real-day billing cycles')
ON CONFLICT(key) DO UPDATE SET amount=EXCLUDED.amount,
 policy_status=EXCLUDED.policy_status,explanation=EXCLUDED.explanation;
