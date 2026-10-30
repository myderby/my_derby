"use client";
import { useEffect, useMemo, useState } from "react";
import { createClient } from "@supabase/supabase-js";

export default function AuthGate({ children }) {
  const client = useMemo(() => {
    const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
    return url && key ? createClient(url, key) : null;
  }, []);
  const [status, setStatus] = useState("loading");
  const [mode, setMode] = useState("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    if (!client) { setStatus("config"); return; }
    let active = true;
    client.auth.getSession().then(({ data, error }) => {
      if (!active) return;
      setStatus(error ? "error" : data.session ? "signed-in" : "signed-out");
      if (error) setMessage(error.message);
    });
    const { data: { subscription } } = client.auth.onAuthStateChange((_event, session) => {
      if (active) setStatus(session ? "signed-in" : "signed-out");
    });
    // Supabase handles an OAuth callback's URL fragment automatically.
    const params = new URLSearchParams(window.location.search);
    const oauthError = params.get("error_description") || params.get("error");
    if (oauthError) setMessage(oauthError);
    return () => { active = false; subscription.unsubscribe(); };
  }, [client]);

  async function submit(event) {
    event.preventDefault();
    if (!client || busy) return;
    if (mode === "signup" && password !== confirm) { setMessage("비밀번호가 일치하지 않습니다."); return; }
    if (password.length < 6) { setMessage("비밀번호는 6자 이상 입력하세요."); return; }
    setBusy(true); setMessage("");
    try {
      const { data, error } = mode === "signup"
        ? await client.auth.signUp({ email: email.trim(), password, options: { emailRedirectTo: window.location.origin + "/" } })
        : await client.auth.signInWithPassword({ email: email.trim(), password });
      if (error) throw error;
      if (mode === "signup" && !data.session) setMessage("인증 메일을 발송했습니다. 이메일 인증 후 로그인해 주세요.");
      else if (mode === "signup") setMessage("회원가입이 완료되었습니다.");
    } catch (error) { setMessage(error.message || "로그인에 실패했습니다."); }
    finally { setBusy(false); }
  }

  async function oauth(provider) {
    if (!client || busy) return;
    setBusy(true); setMessage("");
    try {
      const { error } = await client.auth.signInWithOAuth({
        provider, options: { redirectTo: window.location.origin + "/" }
      });
      if (error) throw error;
    } catch (error) {
      setMessage(error.message || "소셜 로그인에 실패했습니다. 관리자에게 로그인 설정을 확인해 주세요.");
      setBusy(false);
    }
  }

  async function logout() {
    if (!client) return;
    setBusy(true);
    const { error } = await client.auth.signOut();
    if (error) setMessage(error.message);
    setBusy(false);
  }

  if (status === "signed-in") {
    return <><div className="auth-session"><span>MY DERBY</span><button type="button" onClick={logout} disabled={busy}>로그아웃</button></div>{children}</>;
  }
  if (status === "loading") return <main className="auth-screen"><div className="auth-panel"><h1>MY DERBY</h1><p>계정을 확인하고 있습니다.</p></div></main>;
  return <main className="auth-screen"><section className="auth-panel">
    <div className="auth-horse">♞</div>
    <div className="auth-overline">THE OWNER'S JOURNEY</div>
    <h1>MY DERBY</h1>
    <p className="auth-desc">당신의 경주마와 함께 최고의 마주에 도전하세요.</p>
    {status === "config" ? <p className="auth-alert">서비스 인증 설정이 누락되었습니다. 관리자에게 문의해 주세요.</p> :
    <>
      <button className="auth-provider kakao" type="button" onClick={() => oauth("kakao")} disabled={busy}>카카오로 시작하기</button>
      <button className="auth-provider google" type="button" onClick={() => oauth("google")} disabled={busy}>Google(Gmail)로 시작하기</button>
      <div className="auth-divider"><span>또는 이메일로 시작</span></div>
      <div className="auth-tabs"><button type="button" className={mode === "login" ? "active" : ""} onClick={() => { setMode("login"); setMessage(""); }}>로그인</button><button type="button" className={mode === "signup" ? "active" : ""} onClick={() => { setMode("signup"); setMessage(""); }}>회원가입</button></div>
      <form onSubmit={submit}>
        <label>이메일<input autoComplete="email" required type="email" value={email} onChange={e => setEmail(e.target.value)} placeholder="name@example.com" /></label>
        <label>비밀번호<input autoComplete={mode === "signup" ? "new-password" : "current-password"} required minLength={6} type="password" value={password} onChange={e => setPassword(e.target.value)} placeholder="6자 이상" /></label>
        {mode === "signup" && <label>비밀번호 확인<input autoComplete="new-password" required type="password" value={confirm} onChange={e => setConfirm(e.target.value)} placeholder="비밀번호를 다시 입력" /></label>}
        <button className="auth-submit" disabled={busy} type="submit">{busy ? "처리 중…" : mode === "signup" ? "이메일로 회원가입" : "이메일 로그인"}</button>
      </form>
    </>}
    {message && <p className="auth-alert" role="alert">{message}</p>}
    <p className="auth-note">기존 계정으로 로그인하면 이전에 저장한 게임 데이터를 이용할 수 있습니다. 소셜 로그인 계정과 이메일 계정은 자동으로 합쳐지지 않을 수 있습니다.</p>
  </section></main>;
}
