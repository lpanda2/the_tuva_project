{{ config(
     enabled = var('acute_inpatient_enabled',var('tuva_marts_enabled',True))
   )
}}

with distinct_encounters as (
select distinct
  a.encounter_id
, a.patient_id
, b.encounter_start_date
, b.encounter_end_date
from {{ ref('acute_inpatient__encounter_id') }} a
inner join {{ ref('acute_inpatient__encounter_start_and_end_dates') }} b
  on a.encounter_id = b.encounter_id
)

, institutional_claim_details as (
select
  b.encounter_id
, max(a.facility_npi) as facility_npi
, max(ms_drg_code) as ms_drg_code
, max(apr_drg_code) as apr_drg_code
, max(admit_source_code) as admit_source_code
, max(admit_type_code) as admit_type_code
, max(discharge_disposition_code) as discharge_disposition_code
, sum(paid_amount) as inst_paid_amount
, sum(allowed_amount) as inst_allowed_amount
, sum(charge_amount) as inst_charge_amount
, max(data_source) as data_source
from {{ ref('medical_claim') }} a
inner join {{ ref('acute_inpatient__encounter_id') }} b
  on a.claim_id = b.claim_id
  and a.claim_type = 'institutional'
group by 1
)

, professional_claim_details as (
select
  b.encounter_id
, sum(paid_amount) as prof_paid_amount
, sum(allowed_amount) as prof_allowed_amount
, sum(charge_amount) as prof_charge_amount
from {{ ref('acute_inpatient__stg_medical_claim') }} a
inner join {{ ref('acute_inpatient__encounter_id') }} b
  on a.claim_id = b.claim_id
  and a.claim_type = 'professional'
group by 1
)

, patient as (
select distinct
  patient_id
, birth_date
, gender
, race
from {{ ref('acute_inpatient__stg_eligibility') }}
)

, provider as (
select
  a.encounter_id
, max(a.facility_npi) as facility_npi
, b.provider_name
, count(distinct facility_npi) as npi_count
from {{ ref('acute_inpatient__institutional_encounter_id') }} a
left join {{ ref('terminology__provider') }} b
  on a.facility_npi = b.npi
group by 1,3
)

select
  a.encounter_id
, a.encounter_start_date
, a.encounter_end_date
, a.patient_id
, {{ dbt.datediff("birth_date","encounter_end_date","day")}}/365 as admit_age
, e.gender
, e.race
, f.facility_npi
, f.provider_name
, c.ms_drg_code
, j.ms_drg_description
, j.medical_surgical
, c.apr_drg_code
, k.apr_drg_description
, c.admit_source_code
, h.admit_source_description
, c.admit_type_code
, i.admit_type_description
, c.discharge_disposition_code
, g.discharge_disposition_description
, c.inst_paid_amount + d.prof_paid_amount as total_paid_amount
, c.inst_allowed_amount + d.prof_allowed_amount as total_allowed_amount
, c.inst_charge_amount + d.prof_charge_amount as total_charge_amount
, {{ dbt.datediff("a.encounter_start_date","a.encounter_end_date","day") }} as length_of_stay
, case
    when c.discharge_disposition_code = '20' then 1
    else 0
  end mortality_flag
, data_source
from distinct_encounters a
left join institutional_claim_details c
  on a.encounter_id = c.encounter_id
left join professional_claim_details d
  on a.encounter_id = d.encounter_id
left join patient e
  on a.patient_id = e.patient_id
left join provider f
  on a.encounter_id = f.encounter_id
left join {{ ref('terminology__discharge_disposition') }} g
  on c.discharge_disposition_code = g.discharge_disposition_code
left join {{ ref('terminology__admit_source') }} h
  on c.admit_source_code = h.admit_source_code
left join {{ ref('terminology__admit_type') }} i
  on c.admit_type_code = i.admit_type_code
left join {{ ref('terminology__ms_drg') }} j
  on c.ms_drg_code = j.ms_drg_code
left join {{ ref('terminology__apr_drg') }} k
  on c.apr_drg_code = k.apr_drg_code

