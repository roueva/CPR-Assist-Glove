PGDMP                       }            postgres    17.2    17.2 "    w           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                           false            x           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                           false            y           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                           false            z           1262    5    postgres    DATABASE     z   CREATE DATABASE postgres WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE_PROVIDER = libc LOCALE = 'Greek_Greece.1253';
    DROP DATABASE postgres;
                     postgres    false            {           0    0    DATABASE postgres    COMMENT     N   COMMENT ON DATABASE postgres IS 'default administrative connection database';
                        postgres    false    4986            |           0    0    DATABASE postgres    ACL     '   GRANT ALL ON DATABASE postgres TO eva;
                        postgres    false    4986                        2615    16388    pgagent    SCHEMA        CREATE SCHEMA pgagent;
    DROP SCHEMA pgagent;
                     postgres    false            }           0    0    SCHEMA pgagent    COMMENT     6   COMMENT ON SCHEMA pgagent IS 'pgAgent system tables';
                        postgres    false    7                        3079    16389    pgagent 	   EXTENSION     <   CREATE EXTENSION IF NOT EXISTS pgagent WITH SCHEMA pgagent;
    DROP EXTENSION pgagent;
                        false    7            ~           0    0    EXTENSION pgagent    COMMENT     >   COMMENT ON EXTENSION pgagent IS 'A PostgreSQL job scheduler';
                             false    2            �            1259    16619    cpr_sessions    TABLE     �  CREATE TABLE public.cpr_sessions (
    id integer NOT NULL,
    user_id integer,
    compression_count integer NOT NULL,
    session_start timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    session_end timestamp without time zone,
    correct_depth integer DEFAULT 0,
    correct_frequency integer DEFAULT 0,
    correct_angle numeric(6,2) DEFAULT 0,
    session_duration integer DEFAULT 0
);
     DROP TABLE public.cpr_sessions;
       public         heap r       postgres    false            �            1259    16618    cpr_sessions_id_seq    SEQUENCE     �   CREATE SEQUENCE public.cpr_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 *   DROP SEQUENCE public.cpr_sessions_id_seq;
       public               postgres    false    241                       0    0    cpr_sessions_id_seq    SEQUENCE OWNED BY     K   ALTER SEQUENCE public.cpr_sessions_id_seq OWNED BY public.cpr_sessions.id;
          public               postgres    false    240            �            1259    16603    users    TABLE     �  CREATE TABLE public.users (
    id integer NOT NULL,
    username character varying(50) NOT NULL,
    password character varying(255) NOT NULL,
    email character varying(100) NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true,
    reset_token character varying(255),
    reset_token_expiry timestamp without time zone
);
    DROP TABLE public.users;
       public         heap r       postgres    false            �            1259    16602    new_users_id_seq1    SEQUENCE     �   CREATE SEQUENCE public.new_users_id_seq1
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 (   DROP SEQUENCE public.new_users_id_seq1;
       public               postgres    false    239            �           0    0    new_users_id_seq1    SEQUENCE OWNED BY     B   ALTER SEQUENCE public.new_users_id_seq1 OWNED BY public.users.id;
          public               postgres    false    238            �           2604    16622    cpr_sessions id    DEFAULT     r   ALTER TABLE ONLY public.cpr_sessions ALTER COLUMN id SET DEFAULT nextval('public.cpr_sessions_id_seq'::regclass);
 >   ALTER TABLE public.cpr_sessions ALTER COLUMN id DROP DEFAULT;
       public               postgres    false    240    241    241            �           2604    16606    users id    DEFAULT     i   ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.new_users_id_seq1'::regclass);
 7   ALTER TABLE public.users ALTER COLUMN id DROP DEFAULT;
       public               postgres    false    238    239    239            �          0    16390    pga_jobagent 
   TABLE DATA           I   COPY pgagent.pga_jobagent (jagpid, jaglogintime, jagstation) FROM stdin;
    pgagent               postgres    false    223   T$       �          0    16399    pga_jobclass 
   TABLE DATA           7   COPY pgagent.pga_jobclass (jclid, jclname) FROM stdin;
    pgagent               postgres    false    225   �$       �          0    16409    pga_job 
   TABLE DATA           �   COPY pgagent.pga_job (jobid, jobjclid, jobname, jobdesc, jobhostagent, jobenabled, jobcreated, jobchanged, jobagentid, jobnextrun, joblastrun) FROM stdin;
    pgagent               postgres    false    227   �$       �          0    16457    pga_schedule 
   TABLE DATA           �   COPY pgagent.pga_schedule (jscid, jscjobid, jscname, jscdesc, jscenabled, jscstart, jscend, jscminutes, jschours, jscweekdays, jscmonthdays, jscmonths) FROM stdin;
    pgagent               postgres    false    231   �$       �          0    16485    pga_exception 
   TABLE DATA           J   COPY pgagent.pga_exception (jexid, jexscid, jexdate, jextime) FROM stdin;
    pgagent               postgres    false    233   �$       �          0    16499 
   pga_joblog 
   TABLE DATA           X   COPY pgagent.pga_joblog (jlgid, jlgjobid, jlgstatus, jlgstart, jlgduration) FROM stdin;
    pgagent               postgres    false    235   %       �          0    16433    pga_jobstep 
   TABLE DATA           �   COPY pgagent.pga_jobstep (jstid, jstjobid, jstname, jstdesc, jstenabled, jstkind, jstcode, jstconnstr, jstdbname, jstonerror, jscnextrun) FROM stdin;
    pgagent               postgres    false    229   )%       �          0    16515    pga_jobsteplog 
   TABLE DATA           |   COPY pgagent.pga_jobsteplog (jslid, jsljlgid, jsljstid, jslstatus, jslresult, jslstart, jslduration, jsloutput) FROM stdin;
    pgagent               postgres    false    237   F%       t          0    16619    cpr_sessions 
   TABLE DATA           �   COPY public.cpr_sessions (id, user_id, compression_count, session_start, session_end, correct_depth, correct_frequency, correct_angle, session_duration) FROM stdin;
    public               postgres    false    241   c%       r          0    16603    users 
   TABLE DATA           v   COPY public.users (id, username, password, email, created_at, is_active, reset_token, reset_token_expiry) FROM stdin;
    public               postgres    false    239   �'       �           0    0    cpr_sessions_id_seq    SEQUENCE SET     B   SELECT pg_catalog.setval('public.cpr_sessions_id_seq', 28, true);
          public               postgres    false    240            �           0    0    new_users_id_seq1    SEQUENCE SET     @   SELECT pg_catalog.setval('public.new_users_id_seq1', 10, true);
          public               postgres    false    238            �           2606    16625    cpr_sessions cpr_sessions_pkey 
   CONSTRAINT     \   ALTER TABLE ONLY public.cpr_sessions
    ADD CONSTRAINT cpr_sessions_pkey PRIMARY KEY (id);
 H   ALTER TABLE ONLY public.cpr_sessions DROP CONSTRAINT cpr_sessions_pkey;
       public                 postgres    false    241            �           2606    16617    users new_users_email_key 
   CONSTRAINT     U   ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_email_key UNIQUE (email);
 C   ALTER TABLE ONLY public.users DROP CONSTRAINT new_users_email_key;
       public                 postgres    false    239            �           2606    16613    users new_users_pkey1 
   CONSTRAINT     S   ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_pkey1 PRIMARY KEY (id);
 ?   ALTER TABLE ONLY public.users DROP CONSTRAINT new_users_pkey1;
       public                 postgres    false    239            �           2606    16615    users new_users_username_key1 
   CONSTRAINT     \   ALTER TABLE ONLY public.users
    ADD CONSTRAINT new_users_username_key1 UNIQUE (username);
 G   ALTER TABLE ONLY public.users DROP CONSTRAINT new_users_username_key1;
       public                 postgres    false    239            �   4   x��044�4202�54�52V02�21�22�313�42�60�t-K����� ��Z      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      �      x������ � �      t     x�}Uѕ� ��*������"������ٽ\Bfx��̓��,HK�X(	�~�|q�L�HaW�u1Qb�4�ěP�Ы�~��Az���T˚<�v�	�q0�~�Bf��O����$T�_��%|Ȉ^��-�����_�,p#}Y�撮*�iE+sׅ���}А�V��{�A�L�㽌I1�t�2�aM��7�8�:u�-Ă1�Z�x�V����Q*��U�Ō-i��^��e�1�ì���E�����g�d��ȶ��>��U��
U8Q��2�SH3�9���k�s���C��#��ι��֖�>��a��,��P��}v���Q��knЈ����8�Iu�Ε��K[�w�b��g#�3|���wEN�b��xs]�;�����ԧM6Ɍ��]Ѳ�������Rhj�r2�+�g�72�A#N���(2��؍��Q�2������r�]��a�D�ȓDK0���Oz��2�t��jq�G$�̸�a[�]�����Yf��z�c>��]!d�'1���_4M�      r   �  x�m�]s�0���+��n�1		����`?��� KiD����v��:ә3��}�=��8=��a����G��Ģ���~Ѽ�x�'�!��{�	OE�:+w���ܢt���Y&� هr�|"��;dt�aanQ�:��(���aV�+� )��Mն~MG�d�v�Xǉ�Vvd�.�P֪a�a����|%�[�u	��a1�iX��b0�ëIgB��_Oٻ'��٩Ɠg���m4�a��s�����:˧�0*A\�ǼJß��ϾȰ4r�#Ӹ�(cU^u�"�m#����!�`���#���輩J��71��ra��q��;�0�\70�]L,�,���3J�w� �T���%t\'�"���{��*UY1���	�nr?��"�F�̙Mx�*��$��Q2R0=��|�M#�{cDn��;��_����     