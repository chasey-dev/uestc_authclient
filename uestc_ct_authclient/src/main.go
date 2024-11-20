package main

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// 混淆字符串
var confusingString = ">111111111"

var baseHeader = map[string]string{
	"Accept":          "*/*",
	"Accept-Encoding": "gzip, deflate",
	"Accept-Language": "en,zh-CN;q=0.7",
	"Connection":      "keep-alive",
	"Content-Type":    "application/x-www-form-urlencoded; charset=UTF-8",
	"User-Agent":      "Mozilla/5.0 (X11; Linux aarch64; rv:109.0) Gecko/20100101 Firefox/118.0",
}

type loginClient struct {
	c           http.Client
	localIP     string
	cachePath   string
	username    string
	password    string
	exponent    string
	modulus     string
	passwordEnc string
	initHost    string
	loginHost   string
	queryString string
	userIndex   string
}

// 日志级别
const (
	INFO  = "INFO"
	ERROR = "ERROR"
)

// 初始化日志设置
func init() {
	log.SetPrefix("[uestc_ct_authclient] ")
	// 设置日志格式：日期 时间
	log.SetFlags(log.Ldate | log.Ltime)
}

// 自定义日志函数，添加日志级别
func logWithLevel(level string, v ...interface{}) {
	log.Println(fmt.Sprintf("[%s] %s", level, fmt.Sprint(v...)))
}

// 自定义日志函数，格式化输出
func logfWithLevel(level string, format string, v ...interface{}) {
	log.Println(fmt.Sprintf("[%s] %s", level, fmt.Sprintf(format, v...)))
}

func (c *loginClient) Get(urlString string) *http.Response {
	req, err := http.NewRequest("GET", urlString, nil)
	if err != nil {
		logWithLevel(ERROR, "无法创建请求：", err)
		os.Exit(1)
	}

	return c.Do(req)
}

func (c *loginClient) Post(urlString string, body io.Reader) *http.Response {
	req, err := http.NewRequest("POST", urlString, body)
	if err != nil {
		logWithLevel(ERROR, "无法创建请求：", err)
		os.Exit(1)
	}

	return c.Do(req)
}

func (c *loginClient) Do(req *http.Request) *http.Response {
	var dialContext func(ctx context.Context, network, addr string) (net.Conn, error)

	if c.localIP != "" {
		localIP := net.ParseIP(c.localIP)
		if localIP == nil {
			logWithLevel(ERROR, "无效的本地 IP 地址：", c.localIP)
			os.Exit(1)
		}

		dialContext = func(ctx context.Context, network, addr string) (net.Conn, error) {
			localAddr := &net.TCPAddr{
				IP: localIP,
			}
			d := net.Dialer{
				LocalAddr: localAddr,
				Timeout:   30 * time.Second,
				KeepAlive: 30 * time.Second,
			}
			return d.DialContext(ctx, network, addr)
		}
	} else {
		dialer := &net.Dialer{
			Timeout:   30 * time.Second,
			KeepAlive: 30 * time.Second,
		}
		dialContext = dialer.DialContext
	}

	c.c.Transport = &http.Transport{
		DialContext: dialContext,
	}

	for k, v := range baseHeader {
		req.Header.Add(k, v)
	}
	// 禁用自动重定向
	c.c.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		return http.ErrUseLastResponse
	}
	c.c.Timeout = 20 * time.Second

	resp, err := c.c.Do(req)
	if err != nil {
		logWithLevel(ERROR, "无法连接：", err)
		os.Exit(1)
	}

	return resp
}

func (c *loginClient) PasswordEncrypt() {
	if (c.modulus != "") && (c.exponent != "") && (c.password != "") {
		c.password = c.password + confusingString
		// 使用无填充的简单 RSA 加密
		m, _ := new(big.Int).SetString(c.modulus, 16)
		e, _ := new(big.Int).SetString(c.exponent, 16)
		p := new(big.Int).SetBytes([]byte(c.password))
		crypted := new(big.Int).Exp(p, e, m)
		c.passwordEnc = hex.EncodeToString(crypted.Bytes())
	} else if c.passwordEnc != "" {
		return
	} else if c.password == "" {
		logWithLevel(ERROR, "无法加密密码：未提供密码")
		os.Exit(1)
	} else {
		logWithLevel(ERROR, "无法加密密码：参数不足")
		os.Exit(1)
	}
}

func (c *loginClient) myPost(urlString string, reqData map[string]string, respData interface{}) {
	formData := url.Values{}
	for key, value := range reqData {
		formData.Add(key, value)
	}
	body := strings.NewReader(formData.Encode())
	resp := c.Post(urlString, body)
	_ = json.NewDecoder(resp.Body).Decode(respData)
	defer resp.Body.Close()
}

func (c *loginClient) loginInit() {
	urlString := "http://" + c.initHost
	for {
		resp := c.Get(urlString)
		if resp.StatusCode == http.StatusFound {
			urlString = resp.Header.Get("Location")
		} else {
			u, err := url.Parse(urlString)
			if err != nil {
				logWithLevel(ERROR, "返回了非法的 URL '", urlString, "'：", err)
				os.Exit(1)
			}
			c.loginHost = u.Host
			c.queryString = u.RawQuery
			break
		}
	}
}

func (c *loginClient) getEncryptKey() {
	urlString := "http://" + c.loginHost + "/eportal/InterFace.do?method=pageInfo"
	reqData := map[string]string{
		"queryString": c.queryString,
	}
	type respStruct struct {
		PublicKeyExponent string
		PublicKeyModulus  string
	}
	respData := respStruct{}
	c.myPost(urlString, reqData, &respData)
	c.exponent = respData.PublicKeyExponent
	if c.modulus != respData.PublicKeyModulus {
		if c.modulus != "" {
			logWithLevel(INFO, "加密模数已更改")
		}
		c.modulus = respData.PublicKeyModulus
	}
	c.PasswordEncrypt()
}

func (c *loginClient) login() {
	urlString := "http://" + c.loginHost + "/eportal/InterFace.do?method=login"
	reqData := map[string]string{
		"userId":          c.username,
		"password":        c.passwordEnc,
		"service":         "",
		"queryString":     c.queryString,
		"operatorPwd":     "",
		"operatorUserId":  "",
		"validcode":       "",
		"passwordEncrypt": "true",
	}
	type respStruct struct {
		Result    string
		UserIndex string
	}
	respData := respStruct{}
	c.myPost(urlString, reqData, &respData)
	if respData.Result == "success" {
		c.userIndex = respData.UserIndex
		logWithLevel(INFO, "使用账号 '", c.username, "' 登录成功")
	} else {
		logWithLevel(ERROR, "登录尝试失败，账号：'", c.username, "'")
		os.Exit(1)
	}
}

func (c *loginClient) logout() {
	urlString := "http://" + c.initHost + "/eportal/InterFace.do?method=logout"
	reqData := map[string]string{
		"userIndex": c.userIndex,
	}
	type respStruct struct {
		Result string
	}
	respData := respStruct{}
	c.myPost(urlString, reqData, &respData)
	if respData.Result == "success" {
		logWithLevel(INFO, "成功注销")
	} else {
		logWithLevel(ERROR, "注销尝试失败，可能用户索引已过期")
		os.Exit(1)
	}
}

type cache struct {
	Username    string
	PasswordEnc string
	InitHost    string
	UserIndex   string
	Modulus     string
}

func (c *loginClient) loadCache() {
	if c.cachePath == "" {
		return
	}
	path, _ := filepath.Abs(c.cachePath)
	file, err := os.ReadFile(path)
	if err != nil {
		return
	}
	fileCache := cache{}
	err = json.Unmarshal([]byte(file), &fileCache)
	if err != nil {
		logWithLevel(ERROR, "无法解析缓存文件：", err)
		os.Exit(1)
	}
	if c.username == "" {
		c.username = fileCache.Username
	}
	if c.initHost == "" {
		c.initHost = fileCache.InitHost
	}
	c.passwordEnc = fileCache.PasswordEnc
	if c.userIndex == "" {
		c.userIndex = fileCache.UserIndex
	}
	c.modulus = fileCache.Modulus
}

func (c *loginClient) saveCache() {
	if c.cachePath == "" {
		return
	}
	fileCache := cache{
		Username:    c.username,
		PasswordEnc: c.passwordEnc,
		InitHost:    c.initHost,
		UserIndex:   c.userIndex,
		Modulus:     c.modulus,
	}
	file, _ := json.MarshalIndent(fileCache, "", " ")
	path, _ := filepath.Abs(c.cachePath)
	err := os.WriteFile(path, file, 0666)
	if err != nil {
		logWithLevel(ERROR, "无法写入缓存文件：", err)
		os.Exit(1)
	}
}

/*
func (c *loginClient) loadUCIConfig() {
	// 获取用户名
	out, err := exec.Command("uci", "get", "uestc_ct_authclient.@authclient[0].username").Output()
	if err == nil {
		c.username = strings.TrimSpace(string(out))
	}
	// 获取密码
	out, err = exec.Command("uci", "get", "uestc_ct_authclient.@authclient[0].password").Output()
	if err == nil {
		c.password = strings.TrimSpace(string(out))
	}
	// 获取主机
	out, err = exec.Command("uci", "get", "uestc_ct_authclient.@authclient[0].host").Output()
	if err == nil {
		c.initHost = strings.TrimSpace(string(out))
	}
}
*/

func (c *loginClient) run() {
	// 加载UCI配置
	//c.loadUCIConfig()

	/*flag.StringVar(&c.username, "name", c.username, "账号名称，通常为手机号")
	flag.StringVar(&c.password, "passwd", c.password, "账号密码")
	flag.StringVar(&c.initHost, "host", c.initHost, "登录页面的域名，通常为IP地址")*/

	flag.StringVar(&c.username, "name", "", "账号名称，通常为手机号")
	flag.StringVar(&c.password, "passwd", "", "账号密码")
	flag.StringVar(&c.initHost, "host", "172.25.249.64", "登录页面的域名，通常为IP地址")
	flag.StringVar(&c.cachePath, "cache", "", "指定读取和存储缓存的位置，留空以禁用")
	flag.StringVar(&c.userIndex, "index", "", "用户索引，仅用于注销")
	flag.StringVar(&c.localIP, "localip", "", "绑定的本地IP地址")
	logout := flag.Bool("logout", false, "是否注销当前用户")
	flag.Parse()

	if !*logout {
		if (c.cachePath == "") && (c.username == "" || c.password == "") {
			logWithLevel(ERROR,"必须提供用户名、密码")
			os.Exit(1)
		}
		c.loadCache()
		c.loginInit()
		c.getEncryptKey()
		c.login()
		c.saveCache()
	} else {
		c.loadCache()
		c.logout()
	}
}

func main() {
	client := &loginClient{}
	client.run()
}

