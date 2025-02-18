--
-- PostgreSQL database dump
--

-- Dumped from database version 17.2
-- Dumped by pg_dump version 17.2

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgagent; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA pgagent;


ALTER SCHEMA pgagent OWNER TO postgres;

--
-- Name: SCHEMA pgagent; Type: COMMENT; Schema: -; Owner: postgres
--

COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';


--
-- Name: pgagent; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgagent WITH SCHEMA pgagent;


--
-- Name: EXTENSION pgagent; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgagent IS 'A PostgreSQL job scheduler';


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: aed_locations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.aed_locations (
    id bigint NOT NULL,
    latitude double precision NOT NULL,
    longitude double precision NOT NULL,
    name text DEFAULT 'Unknown'::text,
    address text DEFAULT 'Unknown'::text,
    emergency text DEFAULT 'defibrillator'::text,
    operator text DEFAULT 'Unknown'::text,
    indoor boolean,
    access text DEFAULT 'unknown'::text,
    defibrillator_location text DEFAULT 'Not specified'::text,
    level text DEFAULT 'unknown'::text,
    opening_hours text DEFAULT 'unknown'::text,
    phone text DEFAULT 'unknown'::text,
    wheelchair text DEFAULT 'unknown'::text,
    last_updated timestamp without time zone DEFAULT now()
);


ALTER TABLE public.aed_locations OWNER TO postgres;

--
-- Name: cpr_sessions; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.cpr_sessions (
    id integer NOT NULL,
    user_id integer,
    compression_count integer NOT NULL,
    session_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    session_end timestamp without time zone,
    correct_depth integer DEFAULT 0,
    correct_frequency integer DEFAULT 0,
    correct_angle numeric(6,2) DEFAULT 0,
    session_duration integer DEFAULT 0,
    correct_rebound boolean,
    patient_heart_rate integer,
    patient_temperature double precision,
    user_heart_rate integer,
    user_temperature_rate double precision
);


ALTER TABLE public.cpr_sessions OWNER TO postgres;

--
-- Name: cpr_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.cpr_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.cpr_sessions_id_seq OWNER TO postgres;

--
-- Name: cpr_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.cpr_sessions_id_seq OWNED BY public.cpr_sessions.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(255) NOT NULL,
    email character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    reset_token character varying(255),
    reset_token_expiry timestamp without time zone
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: new_users_id_seq1; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.new_users_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.new_users_id_seq1 OWNER TO postgres;

--
-- Name: new_users_id_seq1; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.new_users_id_seq1 OWNED BY public.users.id;


--
-- Name: cpr_sessions id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cpr_sessions ALTER COLUMN id SET DEFAULT nextval('public.cpr_sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.new_users_id_seq1'::regclass);


--
-- Data for Name: pga_jobagent; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_jobagent (jagpid, jaglogintime, jagstation) FROM stdin;
8904	2025-02-14 11:46:55.3205+02	Eva
\.


--
-- Data for Name: pga_jobclass; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_jobclass (jclid, jclname) FROM stdin;
\.


--
-- Data for Name: pga_job; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM stdin;
\.


--
-- Data for Name: pga_schedule; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM stdin;
\.


--
-- Data for Name: pga_exception; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_exception (jexid, jexscid, jexdate, jextime) FROM stdin;
\.


--
-- Data for Name: pga_joblog; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM stdin;
\.


--
-- Data for Name: pga_jobstep; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM stdin;
\.


--
-- Data for Name: pga_jobsteplog; Type: TABLE DATA; Schema: pgagent; Owner: postgres
--

COPY pgagent.pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM stdin;
\.


--
-- Data for Name: aed_locations; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.aed_locations (id, latitude, longitude, name, address, emergency, operator, indoor, access, defibrillator_location, level, opening_hours, phone, wheelchair, last_updated) FROM stdin;
505270304	35.1902343	24.3954758	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.900512
820110916	37.9353892	23.7292033	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	next to entrance	0	unknown	+30 2109316462	unknown	2025-02-11 00:46:37.924645
4081455189	35.171804	33.355588	Unknown	Unknown Address	defibrillator	Cyprus Museum	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.927283
4588746015	34.7117815	32.4885721	Unknown	Unknown Address	defibrillator	Unknown	t	yes	In a intent of a outer wall has green sign ontop	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.928401
5029898023	34.9227308	33.0925873	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.92955
235741229	35.0981553	24.6913702	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.932539
950260942	35.0956726	24.6882034	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.933764
5223410835	34.8704027	33.6091867	Unknown	Unknown Address	defibrillator	Unknown	t	permissive	in the secure zone	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.93565
5223410836	34.870834	33.6084759	Unknown	Unknown Address	defibrillator	Unknown	t	permissive	in the secure zone	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.936884
5223410846	34.7823719	32.4043559	Unknown	Unknown Address	defibrillator	Unknown	t	permissive	reception	unknown	24/7	unknown	yes	2025-02-11 00:46:37.937849
5223410847	34.7131048	33.1672445	Unknown	Unknown Address	defibrillator	Unknown	t	permissive	reception	unknown	24/7	unknown	yes	2025-02-11 00:46:37.938786
999899792	39.5458249	20.784975	EAD	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	08:00-20:00	unknown	unknown	2025-02-11 00:46:37.939835
506469771	35.369877	24.4746675	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.940901
572756049	35.1918698	24.3639035	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.942518
5936662222	34.8895421	33.6369424	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Inside Caffe Nero, at the entrance	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.944168
35033595	40.5559885	22.9932132	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.945403
52547721	37.7393205	26.7471233	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.946416
375202766	35.3668537	24.483629	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	24/7	unknown	no	2025-02-11 00:46:37.947401
388410586	38.1189849	20.5054994	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.948679
961553698	38.1674708	23.7269727	Unknown	Unknown Address	defibrillator	Unknown	t	fixme	opposite to main entrance	0	unknown	unknown	no	2025-02-11 00:46:37.949924
874368339	40.936216	24.4126105	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	0	24/7	unknown	yes	2025-02-11 00:46:37.951061
74271316	40.0019347	23.3832679	Unknown	Unknown Address	defibrillator	Kids Saves Lives	f	unknown	https://kidssavelives.gr	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.952139
620166161	36.5796853	27.1674407	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.953119
528480557	36.8917981	27.2296384	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.953983
287633135	36.8015744	27.0903933	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.954979
9259619756	34.7121802	32.4892843	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Near the arrivals sliding doors, opposite Currency Exchange.	0	unknown	unknown	unknown	2025-02-11 00:46:37.956099
632379729	40.0994481	23.4372306	Unknown	Unknown Address	defibrillator	Κοινότητα Αφύτου	f	restricted	Στην πρόσοψη του κτιρίου της Κοινότητας. Προστατεύεται με κλειδαριά.	unknown	unknown	6909458988	unknown	2025-02-11 00:46:37.957012
849537491	39.4373868	19.9752438	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.957958
152782562	39.5916421	19.9173238	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.959
58705998	35.2981395	25.161389	Unknown	Unknown Address	defibrillator	Unknown	t	customers	In the ticket office	unknown	unknown	unknown	yes	2025-02-11 00:46:37.961426
340308587	35.3389428	25.1412658	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Inside ticket office	0	unknown	unknown	yes	2025-02-11 00:46:37.965207
471557511	35.3378325	25.1357413	Unknown	Unknown Address	defibrillator	Unknown	f	yes	On wall	unknown	unknown	unknown	yes	2025-02-11 00:46:37.966278
927616215	35.3539574	24.4009173	Unknown	Unknown Address	defibrillator	Unknown	f	yes	On wall, outside building	unknown	unknown	unknown	limited	2025-02-11 00:46:37.967381
983210125	40.654084	22.902199	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Main entrance, straight up central in the lobby. Mounted on the second pillar, facing the entrance, between the counters.	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.968373
717934518	35.2330748	23.685155	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.969358
324181366	35.2306162	23.6822473	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	On wall	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.970344
638370393	35.5069971	27.2154334	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.97138
717706420	36.8930258	27.2885753	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.972373
419163213	37.7541623	26.9787041	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.9733
811263724	40.5736322	22.9658268	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.974257
10106389146	34.7417203	32.4318724	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	reception	0	24/7	unknown	yes	2025-02-11 00:46:37.975429
618505456	40.767547	22.1539745	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Not specified	0	unknown	+30 6977605205;+30 6977036124;+30 6947772566	unknown	2025-02-11 00:46:37.976531
1695906	39.623946	19.9214797	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.977495
13436999	39.6235255	19.9235091	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.97851
32773555	40.6629841	22.9338091	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Μέσα στο κλειστό γήπεδο μπάσκετ	0	unknown	unknown	no	2025-02-11 00:46:37.979596
37758746	40.6491926	22.9191421	Unknown	Unknown Address	defibrillator	Unknown	t	private	Πυροσβεστική	0	24/7	unknown	yes	2025-02-11 00:46:37.980591
2547085	40.6613157	22.9340002	Unknown	Unknown Address	defibrillator	Unknown	t	private	Στο γραφείο διευθυντή	1	Mo-Fr 08:30-14:00	unknown	designated	2025-02-11 00:46:37.985376
541842360	40.6489382	22.9185688	Unknown	Unknown Address	defibrillator	Unknown	t	private	Not specified	unknown	Mo-Fr 08:00-20:00	unknown	unknown	2025-02-11 00:46:37.986385
262732776	40.6600645	22.9305475	Unknown	Unknown Address	defibrillator	Unknown	t	private	Not specified	0	Mo-Fr 07:30-16:00	unknown	designated	2025-02-11 00:46:37.98762
387604981	35.5400798	24.1402753	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Not specified	0	unknown	unknown	unknown	2025-02-11 00:46:37.988749
647964144	35.5398725	24.1401554	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Not specified	1	unknown	unknown	unknown	2025-02-11 00:46:37.989655
943050633	40.5238006	22.9762373	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.990787
854071822	37.0791381	22.4285864	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.991967
393319900	39.2388357	20.4825217	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	0	24/7	unknown	no	2025-02-11 00:46:37.993137
678836041	40.6000253	22.9569345	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.99418
65410628	39.1210973	23.7294848	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.995196
561601634	35.4798708	27.1204139	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Located on the outer wall.	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.996195
53236753	35.3617258	24.2596871	Unknown	Unknown Address	defibrillator	Unknown	f	yes	στον τοίχο του κτιρίου	unknown	24/7	unknown	unknown	2025-02-11 00:46:37.997259
592277117	35.5397564	24.1403282	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	0	unknown	unknown	unknown	2025-02-11 00:46:37.998448
156253504	35.1978344	26.2549431	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:37.999448
102800228	35.0090727	25.7397435	AED	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.000505
398013595	38.9308805	20.7720099	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.001492
819118991	39.6156224	19.837848	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.002482
679622584	40.5257968	22.9748451	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Level 1 opposite Gate 7 between SKG Souvenier Shop and Hudon	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.003487
678791317	40.5250884	22.9743635	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Level 1 opposite La Pasteria	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.004472
114754151	40.5243492	22.9750133	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.005431
11734951284	34.8692168	33.6101949	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Before the toilet	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.006392
953520836	40.3222572	21.792351	Unknown	Unknown Address	defibrillator	Πανεπιστήμιο Δυτικής Μακεδονίας	t	yes	Στο κλειστό γυμναστήριο, στο γραφείο των καθηγητών	0	Mo-Fr 08:00-20:00	unknown	yes	2025-02-11 00:46:38.007408
500207900	40.3218622	21.7909244	Unknown	Unknown Address	defibrillator	Πανεπιστήμιο Δυτικής Μακεδονίας	t	yes	δίπλα από την κεντρική είσοδο του κεντρικού Αμφιθεάτρου	0	Mo-Fr 08:00-20:00	unknown	yes	2025-02-11 00:46:38.008436
175443628	40.2786633	21.753683	Unknown	Unknown Address	defibrillator	Πανεπιστήμιο Δυτικής Μακεδονίας	t	yes	Πτέρυγα Β - στο χώρο του κυλικείου	0	Mo-Fr 08:00-20:00	unknown	yes	2025-02-11 00:46:38.009384
832530742	40.2801528	21.755396	Unknown	Unknown Address	defibrillator	Πανεπιστήμιο Δυτικής Μακεδονίας	t	yes	Στο κτήριο Διοίκησης	0	Mo-Fr 08:00-20:00	unknown	yes	2025-02-11 00:46:38.010301
11886409229	35.0179101	34.0471514	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	On the wall opposite the order pickup.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.01124
11904725820	34.7591991	32.4173107	Unknown	Unknown Address	defibrillator	Nereus	t	yes	Inside Nereus hotel reception	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.012182
11904738336	34.7749888	32.4073204	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Inside Tombs of the Kings ticket office	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.013294
11904748954	34.7129065	32.4888253	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Wall mounted between gates 3 and 4	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.014377
11904748955	34.7119394	32.4882363	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Wall mounted next to Frontex office	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.015371
564529606	39.9689956	20.7185202	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.017025
553786621	39.7164968	21.619885	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	Inside Taverna Gardenia	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.018084
759989543	35.2053298	25.7175635	Unknown	Unknown Address	defibrillator	Unknown	f	customers	In the passage to the poolarea in a forme fire hose box.	unknown	24/7	unknown	unknown	2025-02-11 00:46:38.019168
997964114	39.0773947	26.1879252	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.020223
256336510	38.9773518	26.3759527	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.021612
567002841	39.0919046	26.549205	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.02321
505857211	39.1117896	26.5565397	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.02457
773403752	39.2377357	25.9760846	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.025739
347990305	39.2339516	26.2103218	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.026768
125246021	39.0807888	26.1821596	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.027801
194860444	38.975031	26.3691473	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.028814
106512708	39.0366125	26.4564646	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.029864
513935805	39.1576075	26.0603216	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.030912
257597408	39.1318	26.0032362	Μυρσίνη Βουδούρη	Unknown Address	defibrillator	Unknown	f	unknown	Available 24 hours a day. It is locked! In case of an emergency Call +306974535195	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.03209
293042060	39.2347844	25.978891	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.033434
985300372	39.2492753	26.2701591	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.034391
205024299	39.3663213	26.1763737	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.035352
857820189	39.2335237	26.20752	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.036345
547748395	39.2325135	26.2070834	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.037339
347420540	39.0568617	26.5445874	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.038333
25588752	39.0913271	26.5565207	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.039398
923726217	39.3348508	26.3124758	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.040405
208058826	39.0920443	26.5542801	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.041444
408073616	39.0955243	26.5527431	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.042397
763314711	39.0910328	26.5499236	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.043305
579358255	39.1110993	26.5553662	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.044353
141543988	39.1105097	26.5523367	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.045349
476784221	39.1050879	26.5508879	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.046469
632837219	39.1071949	26.5582283	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.047642
501046098	39.1118058	26.5568524	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.048627
442811862	39.1048907	26.5552174	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.049625
599290898	39.102927	26.5541249	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.050606
305164238	39.1051617	26.5601493	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.051781
104050172	39.1028336	26.555838	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.052884
879411482	39.1019886	26.5543582	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.053817
75791994	39.100046	26.5547241	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.054718
368714281	39.1579332	26.0603402	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	The defibrillator is inside the store but there is 24-hour access as during the hours it is closed, there is a person who lives directly above and can open it.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.055634
749458339	39.1031734	26.5560212	HRT Lesvos	Unknown Address	defibrillator	Ελληνική Ομάδα Διάσωσης	t	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.056671
63434802	39.2119856	25.8519094	Unknown	Unknown Address	defibrillator	Unknown	f	permit	It is locked! The keys are held by the agricultural doctor and the president of the village. Their phones are hung on the defibrillator.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.057639
247920788	39.1348693	25.9309896	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.058764
419347854	39.1693733	26.1403138	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Locked at the Rural Medical Office , in the village square, next to the cafe Neon. The key is with the rural doctor and the owner of Neon cafe, Ignatios Giavasis - mobile number 6981031057 Defibrillator instructions in English.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.05969
519778560	39.2605494	26.0746296	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	It is locked, the doctor has keys and at the platanos cafe	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.06063
177077687	39.2473213	26.1048379	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	in the doctor's office of Anemotia and the keys are held by the agricultural doctor.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.061547
91735870	39.2084886	26.2029779	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Available 24 hours a day. It is locked! The keys are held by Koukourouvli Thekla	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.062649
275162962	39.2323468	26.207396	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	available 24/7	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.06364
642819461	39.26192	26.1407365	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.064608
213735444	37.9860248	23.9105461	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.065521
281084389	39.6058867	19.9145376	Unknown	Unknown Address	defibrillator	Unknown	t	unknown	In front of Gate 9	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.06675
12235761901	36.7030426	28.6948411	Unknown	Unknown Address	defibrillator	Unknown	t	yes	Not specified	0	unknown	unknown	unknown	2025-02-11 00:46:38.067891
23495951	38.2348762	22.0789255	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Not specified	0	unknown	unknown	unknown	2025-02-11 00:46:38.068905
12265595721	34.6696847	32.699121	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Inside restaurant	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.069828
657545912	35.34262	25.1344344	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Στον εξωτερικό τοίχο το κτηρίου, ορατό από το πεζοδρόμιο.	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.07086
11688401	37.9961817	23.3662368	Unknown	Unknown Address	defibrillator	Unknown	t	customers	Not specified	0	unknown	unknown	unknown	2025-02-11 00:46:38.071793
672296571	39.1084104	26.5575704	Unknown	Unknown Address	defibrillator	Unknown	f	yes	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.072711
12459040703	41.3199005	19.827265	Unknown	Unknown Address	defibrillator	Unknown	t	yes	AED	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.073942
177009004	37.5662223	22.7967085	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	unknown	unknown	unknown	unknown	2025-02-11 00:46:38.07503
783587464	37.968501	23.7283203	Unknown	Unknown Address	defibrillator	Unknown	f	unknown	Not specified	2	unknown	unknown	unknown	2025-02-11 00:46:38.07604
\.


--
-- Data for Name: cpr_sessions; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.cpr_sessions (id, user_id, compression_count, session_start, session_end, correct_depth, correct_frequency, correct_angle, session_duration, correct_rebound, patient_heart_rate, patient_temperature, user_heart_rate, user_temperature_rate) FROM stdin;
6	1	120	2024-12-17 12:10:22.184533	2024-12-17 12:10:22.184533	100	110	90.00	120	\N	\N	\N	\N	\N
7	1	30	2024-12-17 12:17:50.13181	2024-12-17 12:17:50.13181	13	14	17.00	6	\N	\N	\N	\N	\N
4	8	36	2024-12-07 19:11:10.32055	\N	0	0	0.00	0	\N	\N	\N	\N	\N
2	7	10	2024-12-05 21:29:22.619492	\N	0	0	0.00	0	\N	\N	\N	\N	\N
5	9	100	2024-12-08 18:18:22.850097	\N	0	0	0.00	0	\N	\N	\N	\N	\N
3	1	40	2024-12-05 21:31:16.431174	\N	0	0	0.00	0	\N	\N	\N	\N	\N
8	1	0	2024-12-17 14:18:46.816886	2024-12-17 14:18:46.816886	0	0	0.00	7	\N	\N	\N	\N	\N
9	1	0	2024-12-17 14:18:52.519704	2024-12-17 14:18:52.519704	0	0	0.00	2	\N	\N	\N	\N	\N
10	10	28	2024-12-17 19:06:02.507208	2024-12-17 19:06:02.507208	12	11	3.20	5	\N	\N	\N	\N	\N
11	10	37	2024-12-17 19:18:09.314238	2024-12-17 19:18:09.314238	14	15	4.80	7	\N	\N	\N	\N	\N
14	10	0	2024-12-17 19:22:55.44587	2024-12-17 19:22:55.44587	0	0	0.00	0	\N	\N	\N	\N	\N
13	10	0	2024-12-17 19:22:55.44497	2024-12-17 19:22:55.44497	0	0	0.00	0	\N	\N	\N	\N	\N
12	10	0	2024-12-17 19:22:55.445667	2024-12-17 19:22:55.445667	0	0	0.00	0	\N	\N	\N	\N	\N
15	10	0	2024-12-17 19:23:18.034411	2024-12-17 19:23:18.034411	0	0	0.00	4	\N	\N	\N	\N	\N
16	10	29	2024-12-17 19:36:10.416711	2024-12-17 19:36:10.416711	11	12	3.40	5	\N	\N	\N	\N	\N
17	10	15	2024-12-17 19:39:29.400952	2024-12-17 19:39:29.400952	5	6	1.40	3	\N	\N	\N	\N	\N
18	10	26	2024-12-17 19:48:32.527588	2024-12-17 19:48:32.527588	9	8	3.20	5	\N	\N	\N	\N	\N
19	10	44	2024-12-17 19:51:15.142361	2024-12-17 19:51:15.142361	13	13	3.40	9	\N	\N	\N	\N	\N
20	10	0	2024-12-17 19:51:53.50744	2024-12-17 19:51:53.50744	0	0	0.00	4	\N	\N	\N	\N	\N
21	10	13	2024-12-17 19:54:32.866911	2024-12-17 19:54:32.866911	7	6	1.80	3	\N	\N	\N	\N	\N
22	10	19	2024-12-17 19:54:43.442576	2024-12-17 19:54:43.442576	10	6	1.80	4	\N	\N	\N	\N	\N
23	10	36	2024-12-18 10:48:32.586051	2024-12-18 10:48:32.586051	9	14	5.00	7	\N	\N	\N	\N	\N
24	10	25	2024-12-18 12:12:51.97815	2024-12-18 12:12:51.97815	11	9	2.60	5	\N	\N	\N	\N	\N
25	10	17	2024-12-18 12:24:31.605845	2024-12-18 12:24:31.605845	5	6	2.00	3	\N	\N	\N	\N	\N
26	10	13	2024-12-18 12:30:10.845044	2024-12-18 12:30:10.845044	6	7	1.40	2	\N	\N	\N	\N	\N
27	10	8	2024-12-18 12:30:15.772789	2024-12-18 12:30:15.772789	3	2	0.80	1	\N	\N	\N	\N	\N
28	10	9	2024-12-18 12:33:58.448864	2024-12-18 12:33:58.448864	3	3	1.00	1	\N	\N	\N	\N	\N
29	1	0	2025-01-07 23:30:46.572314	2025-01-07 23:30:46.572314	0	0	0.00	4	\N	\N	\N	\N	\N
30	1	0	2025-01-08 23:00:17.38405	2025-01-08 23:00:17.38405	0	0	0.00	2	\N	\N	\N	\N	\N
31	1	0	2025-01-08 23:03:16.808579	2025-01-08 23:03:16.808579	0	0	0.00	6	\N	\N	\N	\N	\N
32	1	120	2025-01-15 10:00:00	2025-01-15 10:05:00	85	75	30.50	300	t	72	36.5	88	36.8
33	10	0	2025-01-18 21:30:04.157203	2025-01-18 21:30:04.157203	0	0	0.00	0	f	0	0	0	0
34	10	7	2025-01-18 21:30:29.363279	2025-01-18 21:30:29.363279	0	2	0.00	0	f	0	0	0	0
35	10	6	2025-01-18 21:34:30.536958	2025-01-18 21:34:30.536958	0	3	0.00	0	f	0	0	0	0
36	10	20	2025-01-18 21:41:32.850439	2025-01-18 21:41:32.850439	3	10	0.00	0	f	0	0	0	0
37	10	1	2025-01-25 16:11:22.412357	2025-01-25 16:11:22.412357	0	0	0.00	0	f	0	0	0	0
38	10	0	2025-01-27 17:26:06.605365	2025-01-27 17:26:06.605365	0	0	0.00	0	f	0	0	0	0
39	10	8	2025-01-27 18:57:09.743752	2025-01-27 18:57:09.743752	0	2	0.00	0	f	0	0	0	0
40	10	0	2025-01-27 22:28:10.084682	2025-01-27 22:28:10.084682	0	0	0.00	0	f	0	0	0	0
41	10	0	2025-01-27 22:54:13.664965	2025-01-27 22:54:13.664965	0	0	0.00	0	f	0	0	0	0
42	10	0	2025-01-28 00:37:03.000157	2025-01-28 00:37:03.000157	0	0	0.00	0	f	0	0	0	0
43	10	0	2025-01-28 00:37:13.922366	2025-01-28 00:37:13.922366	0	0	0.00	0	f	0	0	0	0
44	10	0	2025-01-28 16:58:56.121264	2025-01-28 16:58:56.121264	0	0	0.00	0	f	0	0	0	0
45	10	0	2025-01-28 18:08:39.375726	2025-01-28 18:08:39.375726	0	0	0.00	0	f	0	0	0	0
46	10	0	2025-01-28 19:20:21.960476	2025-01-28 19:20:21.960476	0	0	0.00	0	f	0	0	0	0
47	10	0	2025-01-28 19:20:37.055858	2025-01-28 19:20:37.055858	0	0	0.00	0	f	0	0	0	0
48	10	11	2025-01-28 20:00:04.893842	2025-01-28 20:00:04.893842	0	3	0.00	0	f	0	0	0	0
49	10	11	2025-01-28 20:00:34.016874	2025-01-28 20:00:34.016874	0	3	0.00	0	f	0	0	0	0
50	10	0	2025-01-28 20:03:11.465112	2025-01-28 20:03:11.465112	0	0	0.00	0	f	0	0	0	0
51	10	13	2025-01-28 20:27:00.495937	2025-01-28 20:27:00.495937	0	3	0.00	0	f	0	0	0	0
52	10	8	2025-01-28 20:27:42.405902	2025-01-28 20:27:42.405902	0	2	0.00	0	f	0	0	0	0
53	10	2	2025-01-28 20:38:08.251705	2025-01-28 20:38:08.251705	0	1	0.00	0	f	0	0	0	0
54	10	0	2025-02-04 17:29:17.308269	2025-02-04 17:29:17.308269	0	0	0.00	0	f	0	0	0	0
55	10	0	2025-02-05 14:17:43.941925	2025-02-05 14:17:43.941925	0	0	0.00	0	f	0	0	0	0
56	10	4	2025-02-08 17:32:30.141691	2025-02-08 17:32:30.141691	0	1	0.00	0	f	0	0	0	0
57	10	0	2025-02-09 16:07:10.676866	2025-02-09 16:07:10.676866	0	0	0.00	0	f	0	0	0	0
58	10	1	2025-02-09 20:39:24.115364	2025-02-09 20:39:24.115364	0	0	0.00	0	f	0	0	0	0
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, username, password, email, created_at, is_active, reset_token, reset_token_expiry) FROM stdin;
9	Teo	$2b$12$/vYIikCPU/LzQW3MODS7EedA4OpvfpnPMsc4waHXKmMTg7/Ij0kYK	ioannis@gmail.com	2024-12-08 18:17:47.55461+02	t	\N	\N
7	anti	$2b$12$5.2t7BjksjvZkC3i50KRleNqYeg9RXXBc9XHXKAivsy5PH56Bl412	anti@g.com	2024-12-05 21:28:59.670316+02	t	\N	\N
1	Eva	$2b$12$4SPiKuNvO5fMPBqxHuDEL.sPTKy34n1PzvTNzhbRSyuwRVJw3R54i	evarouka@gmail.com	2024-12-04 18:08:38.746098+02	t	\N	\N
10	test	$2b$12$sWPxzyiq1/oxoA5azRmYFec8yBPCxbut9H6be5v5VUBK86c7syel2	test@test.com	2024-12-17 12:55:01.665444+02	t	\N	\N
8	Miso	$2b$12$ng4DvgVpg.uHoMrlXksnpOMBeJ.NKgFCPjnKPPgcCUnHSOG7z6rGu	misop@physics.kr	2024-12-07 19:10:18.671026+02	t	\N	\N
\.


--
-- Name: cpr_sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.cpr_sessions_id_seq', 58, true);


--
-- Name: new_users_id_seq1; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.new_users_id_seq1', 10, true);


--
-- Name: aed_locations aed_locations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.aed_locations
    ADD CONSTRAINT aed_locations_pkey PRIMARY KEY (id);


--
-- Name: cpr_sessions cpr_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.cpr_sessions
    ADD CONSTRAINT cpr_sessions_pkey PRIMARY KEY (id);


--
-- Name: users new_users_email_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_email_key UNIQUE (email);


--
-- Name: users new_users_pkey1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_pkey1 PRIMARY KEY (id);


--
-- Name: users new_users_username_key1; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_username_key1 UNIQUE (username);


--
-- PostgreSQL database dump complete
--

